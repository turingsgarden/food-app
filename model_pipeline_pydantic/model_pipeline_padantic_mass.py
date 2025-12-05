
import os
import ssl
import certifi
from PIL import Image
import numpy as np
from io import BytesIO
from pydantic_ai import Agent, BinaryContent
from pydantic import BaseModel, Field, field_validator
from typing import List

# -------------------- SSL Certificate Fix --------------------
# Set SSL certificate path
os.environ['SSL_CERT_FILE'] = certifi.where()

class FoodItem(BaseModel):
    name: str = Field(description="Food name")
    predicted_mass_g: float = Field(description="Predicted mass in grams")
    confidence: float = Field(description="Overall confidence (0-1) including recognition accuracy and mass estimation reliability", ge=0, le=1)

class MassEstimationOutput(BaseModel):
    food_items: List[FoodItem] = Field(description="List of identified food items")
    total_mass_g: float = Field(description="Total mass in grams")
    volume_cm3: float = Field(description="Calculated volume in cubic centimeters")
    
    # Pydantic V2 style validators
    @field_validator('total_mass_g')
    @classmethod
    def validate_total_mass(cls, v):
        if v <= 0:
            raise ValueError('Total mass must be positive')
        if v > 5000:  # Assuming single meal doesn't exceed 5kg
            raise ValueError('Total mass is abnormal, please check estimation results')
        return round(v, 2)
    
    @field_validator('food_items')
    @classmethod
    def validate_food_items(cls, v):
        if not v:
            raise ValueError('At least one food item must be identified')
        return v
    
    @field_validator('volume_cm3')
    @classmethod
    def validate_volume(cls, v):
        if v < 0:
            raise ValueError('Volume cannot be negative')
        return round(v, 2)

def calculate_volume_from_depth_and_mask(depth_img: Image.Image, segmentation_img: Image.Image) -> float:
    """
    Calculate food volume based on depth map and segmentation mask
    
    Args:
        depth_img: 16-bit depth map PIL image (1 meter = 10,000 units)
        segmentation_img: PNG segmentation mask PIL image
        
    Returns:
        float: Volume value in cubic centimeters (cm³)
    """
    # Convert to numpy arrays
    depth_array = np.array(depth_img)  # 16-bit depth values
    mask_array = np.array(segmentation_img)
    
    print(f"📊 Depth image info: shape={depth_array.shape}, dtype={depth_array.dtype}, range=[{depth_array.min()}, {depth_array.max()}]")
    print(f"📊 Mask image info: shape={mask_array.shape}, dtype={mask_array.dtype}")
    
    # Process segmentation mask
    if len(mask_array.shape) == 3:
        # RGB mask - assume non-black regions as food areas
        mask_binary = np.any(mask_array > 10, axis=2)
        print("🎭 Using RGB mask (non-black regions as food)")
    else:
        # Grayscale mask - assume non-zero regions as food areas
        mask_binary = mask_array > 0
        print("🎭 Using grayscale mask (non-zero regions as food)")
    
    # Ensure depth map is single channel
    if len(depth_array.shape) == 3:
        print("⚠️ Depth image has multiple channels, using first channel")
        depth_array = depth_array[:, :, 0]
    
    # Apply mask to get depth values in food regions
    food_depth_values = depth_array[mask_binary]
    
    if len(food_depth_values) == 0:
        print("⚠️ No food regions found in mask")
        return 0.0
    
    print(f"📊 Food region stats: {len(food_depth_values)} pixels, depth range=[{food_depth_values.min()}, {food_depth_values.max()}] units")
    
    # Convert depth units: 10,000 units = 1 meter = 100 cm
    # Therefore: depth_cm = depth_units × (100 / 10000) = depth_units × 0.01
    food_depth_cm = food_depth_values * 0.01  # Convert to centimeters
    
    # Calculate average depth (cm)
    avg_depth_cm = np.mean(food_depth_cm)
    
    # Calculate number of pixels in mask region
    pixel_count = np.sum(mask_binary)
    
    # Estimate actual area per pixel (requires camera calibration parameters)
    # Using a reasonable estimate here, you can adjust based on actual camera parameters
    # This value needs calibration based on your camera focal length and resolution
    pixel_area_cm2 = 5.957e-3  # cm² per pixel  from nutrition5k paper
    
    print(f"📊 Volume calculation:")
    print(f"   - Pixel count: {pixel_count}")
    print(f"   - Average depth: {avg_depth_cm:.2f} cm")
    print(f"   - Pixel area: {pixel_area_cm2} cm²")
    
    # Calculate volume: area × average depth
    volume_cm3 = pixel_count * pixel_area_cm2 * avg_depth_cm
    
    print(f"📊 Calculated volume: {volume_cm3:.2f} cm³")
    
    return volume_cm3



class FoodMassEstimationService:
    def __init__(self):
        # Use Gemini 2.5 Pro model
        self.mass_agent = Agent(
            "google-gla:gemini-2.5-pro",  # Gemini 2.5 Pro model
            output_type=MassEstimationOutput,
            system_prompt=(
                "You are a professional food analysis expert. "
                "Analyze food images to identify dishes, ingredients, and estimate nutrition. "
                "Be thorough and accurate in your analysis. "
                "IMPORTANT INSTRUCTIONS:\n"
                "1. For units: use 'g' for solid ingredients, 'ml' for liquid ingredients\n"
                "2. For nutrition information: use kcal for calories, g for protein/fat/carbs/fiber/sugar, mg for sodium\n"
                "3. For dish names: identify ONLY the main dish (the most prominent food item in the image)\n"
                "4. For ingredients: DO NOT include source dish names in the ingredient list\n"
                "5. Estimate quantities and nutrition based on standard portion sizes\n"
                "6. ADDITIONAL DATA: You will receive RGB image, segmentation mask, and depth map for analysis\n"
                "7. Use the depth map and segmentation mask to improve volume and mass estimation accuracy\n"
                "Identify all visible ingredients with quantities using correct units, "
                "estimate hidden cooking ingredients, and calculate nutrition information."
            )
        )
    
    def preprocess_image_to_bytes(self, pil_img: Image.Image) -> bytes:
        """Convert PIL image to bytes"""
        buffer = BytesIO()
        # Keep original format for PNG images, use JPEG for other formats
        if pil_img.format == 'PNG':
            pil_img.save(buffer, format="PNG")
        else:
            pil_img.save(buffer, format="JPEG", quality=95)
        buffer.seek(0)
        return buffer.getvalue()
    
    def run_estimation(
        self,
        rgb_img: Image.Image,
        segmentation_img: Image.Image,
        depth_img: Image.Image, 
        user_id: str
    ) -> MassEstimationOutput:
        
        # Calculate volume
        print("🔍 Calculating volume from depth and mask...")
        volume_cm3 = calculate_volume_from_depth_and_mask(depth_img, segmentation_img)
        
        # Prepare input data
        rgb_bytes = self.preprocess_image_to_bytes(rgb_img)
        mask_bytes = self.preprocess_image_to_bytes(segmentation_img)
        depth_bytes = self.preprocess_image_to_bytes(depth_img)
        
        prompt = (
            f"Comprehensively analyze this food image. User ID: {user_id}\n"
            f"IMPORTANT: Follow these exact formats:\n"
            f"- Use 'g' for solids, 'ml' for liquids\n" 
            f"- Nutrition: calories(kcal), protein(g), fat(g), carbs(g), fiber(g), sugar(g), sodium(mg)\n"
            f"- Return ONLY the main dish name\n"
            f"- For ingredients: List only name, quantity, unit - NO source dish names\n"
            f"- ADDITIONAL DATA: You have been provided with RGB image, segmentation mask, and depth map\n"
            f"- CALCULATED VOLUME: {volume_cm3:.2f} cm³ - use this to improve mass estimation accuracy\n"
            f"- Be precise with quantities and nutrition estimates"
        )
        
        result = self.mass_agent.run_sync(
            [
                prompt,
                BinaryContent(data=rgb_bytes, media_type="image/jpeg"),
                BinaryContent(data=mask_bytes, media_type="image/png"),
                BinaryContent(data=depth_bytes, media_type="image/png"),  # 16-bit PNG
            ]
        )
        
       
        output_data = result.output.dict()
        output_data['volume_cm3'] = volume_cm3
        
        return MassEstimationOutput(**output_data)

# Test function
def test_with_real_data():
    """Test with real data"""
    try:
        # Initialize service
        service = FoodMassEstimationService()
        
        # Load your actual image files here
        # Replace with your actual file paths
        rgb_img = Image.open("path/to/your/rgb_image.jpg")
        segmentation_img = Image.open("path/to/your/segmentation_mask.png")
        depth_img = Image.open("path/to/your/depth_image.png")  # 16-bit depth map
        
        print("📷 Image info:")
        print(f"   RGB: {rgb_img.size}, {rgb_img.mode}")
        print(f"   Mask: {segmentation_img.size}, {segmentation_img.mode}")
        print(f"   Depth: {depth_img.size}, {depth_img.mode}")
        
        # Run estimation
        result = service.run_estimation(
            rgb_img=rgb_img,
            segmentation_img=segmentation_img,
            depth_img=depth_img,
            user_id="test_user"
        )
        
        print("\n✅ Estimation Results:")
        print(f"Total Mass: {result.total_mass_g}g")
        print(f"Calculated Volume: {result.volume_cm3}cm³")
        for i, item in enumerate(result.food_items):
            print(f"Food {i+1}: {item.name} - {item.predicted_mass_g}g (confidence: {item.confidence:.2f})")
            
        return result
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()

# Test code
if __name__ == "__main__":
    try:
        print("Initializing Food Mass Estimation Service...")
        service = FoodMassEstimationService()
        print("✅ Service initialized successfully!")
        
        # Run real data test
        test_with_real_data()
        
    except Exception as e:
        print(f"❌ Initialization failed: {e}")
        print("Please check:")
        print("1. Google API key is properly set")
        print("2. Network connection is working")
        print("3. Dependencies are installed correctly")