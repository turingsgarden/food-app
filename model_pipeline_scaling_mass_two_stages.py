import os
import ssl
import certifi
from PIL import Image
import numpy as np
from io import BytesIO
from pydantic_ai import Agent, BinaryContent
from pydantic import BaseModel, Field, field_validator
from typing import List, Optional


os.environ['SSL_CERT_FILE'] = certifi.where()

# ==================== STAGE 1: Food Identification & Mass Estimation ====================

class FoodItem(BaseModel):
    """Individual food item with mass estimation"""
    name: str = Field(description="Food name (e.g., 'almonds', 'broccoli')")
    predicted_mass_g: float = Field(description="Predicted mass in grams", gt=0)
    identification_confidence: float = Field(
        description="Confidence in food identification (0-1)", 
        ge=0, 
        le=1
    )
    mass_confidence: float = Field(
        description="Confidence in mass estimation (0-1)", 
        ge=0, 
        le=1
    )
    
    @field_validator('predicted_mass_g')
    @classmethod
    def validate_mass(cls, v):
        if v > 2000:  # Single food item shouldn't exceed 2kg
            raise ValueError(f'Single food item mass {v}g seems unrealistic')
        return round(v, 1)


class Stage1Output(BaseModel):
    """Output from Stage 1: Food identification and mass estimation"""
    food_items: List[FoodItem] = Field(description="List of identified food items")
    total_mass_g: float = Field(description="Total mass in grams")
    scale_factor_used: float = Field(description="Scale factor used for depth calculation")
    notes: Optional[str] = Field(
        default=None,
        description="Any observations about image quality, occlusions, or uncertainties"
    )
    
    @field_validator('food_items')
    @classmethod
    def validate_food_items(cls, v):
        if not v:
            raise ValueError('At least one food item must be identified')
        return v
    
    @field_validator('total_mass_g')
    @classmethod
    def validate_total(cls, v, info):
        # Check if total matches sum of individual items
        food_items = info.data.get('food_items', [])
        if food_items:
            calculated_total = sum(item.predicted_mass_g for item in food_items)
            if abs(calculated_total - v) > 1.0:  # Allow 1g tolerance
                raise ValueError(
                    f'Total mass {v}g does not match sum of items {calculated_total}g'
                )
        return round(v, 1)

# ==================== STAGE 2: Nutrition Analysis & Verification ====================

class NutritionInfo(BaseModel):
    """Nutrition information for a single food item"""
    food_name: str = Field(description="Food name (must match Stage 1)")
    mass_g: float = Field(description="Mass in grams (from Stage 1)")
    
    # Macronutrients
    calories_kcal: float = Field(description="Total calories in kcal", ge=0)
    protein_g: float = Field(description="Protein in grams", ge=0)
    carbs_g: float = Field(description="Carbohydrates in grams", ge=0)
    fat_g: float = Field(description="Fat in grams", ge=0)
    fiber_g: float = Field(description="Dietary fiber in grams", ge=0)
    
    # Micronutrients (optional but recommended)
    sodium_mg: Optional[float] = Field(default=None, description="Sodium in mg", ge=0)
    sugar_g: Optional[float] = Field(default=None, description="Sugar in grams", ge=0)
    
    nutrition_confidence: float = Field(
        description="Confidence in nutrition estimation (0-1)", 
        ge=0, 
        le=1
    )
    
    # @field_validator('calories_kcal')
    # @classmethod
    # def validate_calories(cls, v, info):
    #     """Verify calories using Atwater coefficients: 4-4-9 rule"""
    #     protein = info.data.get('protein_g', 0)
    #     carbs = info.data.get('carbs_g', 0)
    #     fat = info.data.get('fat_g', 0)
        
    #     # Calculate theoretical calories
    #     theoretical_cal = (protein * 4) + (carbs * 4) + (fat * 9)
        
    #     # Handle very low calorie foods (like lettuce, celery)
    #     if theoretical_cal < 10 and v < 10:
    #         return round(v, 1)
        
    #     # Handle cases where macros are all zero but calories are very small
    #     # (model might have made a minor error but it's negligible)
    #     if theoretical_cal == 0 and v < 15:
    #         return round(v, 1)
        
    #     # Reject cases where macros are zero but calories are significant
    #     if theoretical_cal == 0 and v >= 15:
    #         raise ValueError(
    #             f'Calorie mismatch: Estimated {v} kcal, but '
    #             f'all macros are 0g (Protein:{protein}g, Carbs:{carbs}g, Fat:{fat}g). '
    #             f'Please provide non-zero macronutrient estimates for foods with calories.'
    #         )
        
    #     # Normal validation with 30% tolerance
    #     tolerance = 0.3
    #     lower_bound = theoretical_cal * (1 - tolerance)
    #     upper_bound = theoretical_cal * (1 + tolerance)
        
    #     if not (lower_bound <= v <= upper_bound):
    #         raise ValueError(
    #             f'Calorie mismatch: Estimated {v} kcal, but '
    #             f'macros suggest {theoretical_cal:.1f} kcal '
    #             f'(Protein:{protein}g×4 + Carbs:{carbs}g×4 + Fat:{fat}g×9). '
    #             f'Please verify your estimates.'
    #         )
        
    #     return round(v, 1)


class FoodNutritionAnalyzer:
    """Two-stage food nutrition analysis service"""
    
    def __init__(self, model: str = "gemini-2.0-flash-exp"):
        self.model = model
        
        # Stage 1 Agent
        self.stage1_agent = Agent(
            model,
            output_type=Stage1Output,
            system_prompt=self._get_stage1_system_prompt(),
            retries=5
        )
        
        # Stage 2 Agent with retry feedback
        self.stage2_agent = Agent(
            model,
            output_type=Stage2Output,
            system_prompt=self._get_stage2_system_prompt(),
            retries=10,
           
            retry_prompt=(
                " VALIDATION FAILED - This is retry attempt {retry_count}/{max_retries}\n\n"
                "ERROR: {error}\n\n"
                "INSTRUCTIONS FOR THIS RETRY:\n"
                "1. The previous output exceeded validation boundaries\n"
                "2. Review the 4-4-9 rule: Calories = (Protein×4) + (Carbs×4) + (Fat×9)\n"
                "3. Ensure your macronutrient estimates align with your calorie estimate\n"
                "4. If theoretical calories = 0 but you estimated >30 kcal, provide non-zero macros\n"
                "5. Keep estimates within ±30% of theoretical calories\n"
                "6. Be conservative and realistic - avoid extreme values\n\n"
                "Please revise your nutrition estimates NOW."
            )
        )
    
    def _get_stage1_system_prompt(self) -> str:
        return """You are a food recognition and mass estimation expert.

TASK: Identify foods and estimate mass in grams.

DATA SOURCES:
1. RGB Image (PRIMARY): Food types, colors, textures, portion sizes
2. Segmentation Mask (SECONDARY): Food boundaries (ignore if poor quality)
3. Depth Map (TERTIARY): Height/volume (ignore if unreliable)

STRATEGY:
- Visual recognition first
- Cross-reference portion knowledge (e.g., egg ≈60g)
- Use segmentation/depth only when helpful
- Provide realistic confidence scores

OUTPUT:
- List each distinct food item
- Ensure total_mass = sum of individual items"""

    def _get_stage2_system_prompt(self) -> str:
        return """You are a nutrition analyst. Calculate nutrition info using the 4-4-9 rule.

ATWATER COEFFICIENTS:
- Protein: 4 kcal/g
- Carbs: 4 kcal/g
- Fat: 9 kcal/g

PROCESS:
1. Look up nutrition values per 100g
2. Scale to actual mass from Stage 1
3. VERIFY: Theoretical calories = (P×4) + (C×4) + (F×9)
4. Ensure estimated calories within ±30% of theoretical
5. If theoretical = 0 but you estimate >30 kcal, provide non-zero macros

CRITICAL RULES:
- Never output all-zero macros (P=0, C=0, F=0) with calories >30
- Calories must match macros within 30% tolerance
- Be conservative - avoid extreme values
- Set verification_passed=True only if math checks out

OUTPUT:
- Nutrition for EVERY food item from Stage 1
- Show verification logic in notes"""

    def _preprocess_image_to_bytes(self, pil_img: Image.Image) -> bytes:
        """Convert PIL image to JPEG bytes"""
        buffer = BytesIO()
        pil_img.save(buffer, format="JPEG", quality=95)
        buffer.seek(0)
        return buffer.getvalue()
    
    def stage1_estimate_mass(
        self,
        rgb_img: Image.Image,
        segmentation_img: Image.Image,
        depth_img: Image.Image,
        scale_factor: float,
        user_id: str
    ) -> Stage1Output:
        """Stage 1: Identify foods and estimate mass"""
        
        rgb_bytes = self._preprocess_image_to_bytes(rgb_img)
        seg_bytes = self._preprocess_image_to_bytes(segmentation_img)
        depth_bytes = self._preprocess_image_to_bytes(depth_img)
        
        prompt = f"""Identify foods and estimate mass.

USER: {user_id}
SCALE FACTOR: {scale_factor}

INPUT:
- Image 1: RGB photograph
- Image 2: Segmentation mask
- Image 3: Depth map (blue=close, red=far)

INSTRUCTIONS:
1. Identify all distinct food items in RGB image
2. Estimate mass using visual recognition + portion knowledge
3. Use segmentation/depth only if helpful
4. Provide realistic confidence scores

Begin:"""

        result = self.stage1_agent.run_sync([
            prompt,
            BinaryContent(data=rgb_bytes, media_type="image/jpeg"),
            BinaryContent(data=seg_bytes, media_type="image/jpeg"),
            BinaryContent(data=depth_bytes, media_type="image/jpeg"),
        ])
        
        return result.output
    
    def stage2_analyze_nutrition(
        self,
        stage1_result: Stage1Output,
        user_id: str
    ) -> Stage2Output:
        """Stage 2: Calculate nutrition and verify using 4-4-9 rule"""
        
        food_summary = "\n".join([
            f"- {item.name}: {item.predicted_mass_g}g "
            f"(ID: {item.identification_confidence:.2f}, Mass: {item.mass_confidence:.2f})"
            for item in stage1_result.food_items
        ])
        
        prompt = f"""Calculate nutrition using 4-4-9 rule.

USER: {user_id}

STAGE 1 RESULTS:
{food_summary}

TOTAL MASS: {stage1_result.total_mass_g}g
{f"NOTES: {stage1_result.notes}" if stage1_result.notes else ""}

TASK:
1. For each food item, provide nutrition breakdown
2. Use USDA database, scale to actual mass
3. VERIFY using 4-4-9 rule:
   Theoretical Calories = (Protein×4) + (Carbs×4) + (Fat×9)
4. Ensure your estimate within ±30% of theoretical
5. If macros all = 0, calories must be ≤30 kcal
6. Calculate totals and set verification_passed=True if valid

EXAMPLE:
20g almonds:
- Protein: 4.2g → 16.8 kcal
- Carbs: 2.5g → 10.0 kcal
- Fat: 10.8g → 97.2 kcal
- Theoretical: 124 kcal
- Estimate: 120-130 kcal ✓

Begin:"""

        result = self.stage2_agent.run_sync(prompt)
        
        return result.output
    
    def analyze_complete(
        self,
        rgb_img: Image.Image,
        segmentation_img: Image.Image,
        depth_img: Image.Image,
        scale_factor: float,
        user_id: str = "default_user"
    ) -> tuple[Stage1Output, Stage2Output]:
        """Complete two-stage analysis pipeline"""
        
        print(f"\n{'='*60}")
        print(f"STAGE 1: Food Identification & Mass Estimation")
        print(f"{'='*60}")
        
        stage1_result = self.stage1_estimate_mass(
            rgb_img, segmentation_img, depth_img, scale_factor, user_id
        )
        
        print(f" Stage 1 Complete - Found {len(stage1_result.food_items)} food items")
        print(f"Total Mass: {stage1_result.total_mass_g}g\n")
        
        for item in stage1_result.food_items:
            print(f"  • {item.name}: {item.predicted_mass_g}g "
                  f"(conf: {item.identification_confidence:.2f}/{item.mass_confidence:.2f})")
        
        print(f"\n{'='*60}")
        print(f"STAGE 2: Nutrition Analysis & Verification")
        print(f"{'='*60}")
        
        stage2_result = self.stage2_analyze_nutrition(stage1_result, user_id)
        
        print(f"Stage 2 Complete")
        print(f"Verification: {'✓ PASSED' if stage2_result.verification_passed else '✗ FAILED'}")
        print(f"\nTOTAL NUTRITION:")
        print(f"  Calories: {stage2_result.total_calories_kcal} kcal")
        print(f"  Protein: {stage2_result.total_protein_g}g")
        print(f"  Carbs: {stage2_result.total_carbs_g}g")
        print(f"  Fat: {stage2_result.total_fat_g}g")
        print(f"  Fiber: {stage2_result.total_fiber_g}g")
        
        if stage2_result.verification_notes:
            print(f"\nNotes: {stage2_result.verification_notes}")
        
        return stage1_result, stage2_result

# ==================== Testing ====================

if __name__ == "__main__":
    try:
        print("Initializing Food Nutrition Analyzer (Two-Stage Architecture)...")
        analyzer = FoodNutritionAnalyzer()
        print("Service initialized successfully!")
        print("\nService is ready to use with:")
        print("  - Stage 1: Food identification + mass estimation")
        print("  - Stage 2: Nutrition analysis + 4-4-9 verification")
        print("\nTo use:")
        print("  stage1, stage2 = analyzer.analyze_complete(rgb, seg, depth, scale)")
        
    except Exception as e:
        print(f"Initialization failed: {e}")
        print("\nPlease check:")
        print("1. GOOGLE_API_KEY environment variable is set")
        print("2. pydantic-ai package is installed")
        print("3. Network connection is working")