async function loadImages() {
    const grid = document.getElementById("dish-grid");
    grid.innerHTML = "Loading...";

    try {
        const res = await fetch("/developer/api/images");
        const imagePaths = await res.json();

        grid.innerHTML = "";

        for (const path of imagePaths) {
            const card = document.createElement("div");
            card.className = "card";

            const img = document.createElement("img");
            img.src = path.url;
            img.alt = "Food image";
            img.onclick = () => {
                window.open(`/developer/view?image_url=${encodeURIComponent(img.src)}`, '_blank');
            };

            card.appendChild(img);
            grid.appendChild(card);
        }
    } catch (err) {
        console.error("Image fetch error:", err);
        grid.innerHTML = "<p style='color:red;'>Error loading images. Check console.</p>";
    }
}

window.onload = loadImages;


