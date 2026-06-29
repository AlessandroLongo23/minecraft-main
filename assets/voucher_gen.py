"""AI icon generation engines for vouchers. Keys from env:
  PIXELLAB_SECRET   (PixelLab)        RD_API_TOKEN (Retro Diffusion)
Each *_icon() returns an RGBA PIL.Image (the icon only). Verify exact request
fields against current vendor docs before the first paid run:
  PixelLab: https://www.pixellab.ai/pixellab-api
  Retro Diffusion: https://github.com/Retro-Diffusion/api-examples"""
import os, io, base64
from PIL import Image

STYLE_STRENGTH = 60      # PixelLab Bitforge reference-style adherence
IMG2IMG_STRENGTH = 0.7   # Retro Diffusion input_image denoise strength

def _b64_png(img_or_path):
    if isinstance(img_or_path, str):
        with open(img_or_path, "rb") as f: return base64.b64encode(f.read()).decode()
    buf = io.BytesIO(); img_or_path.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()

def save_icon(img, path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True); img.save(path)

# ---- PixelLab (Bitforge) ----
# The SDK takes PIL images DIRECTLY for each reference channel:
#   init_image (+init_image_strength) = img2img layout/structure reference
#   color_image                       = forced palette
#   style_image (+style_strength)     = visual-style reference (e.g. a real voucher icon)
def pixellab_icon(prompt, size, init_image=None, style_image=None, color_image=None,
                  init_image_strength=300, style_strength=STYLE_STRENGTH,
                  no_background=True, seed=0):
    # We POST /generate-image-bitforge directly and parse the image ourselves,
    # reusing the SDK only for auth + base64 encoding. This bypasses a bug where
    # the SDK's Usage response model rejects the free-trial 'generations' usage type.
    import requests, pixellab
    from pixellab.models import Base64Image
    secret = os.environ.get("PIXELLAB_SECRET")
    if not secret:
        raise RuntimeError("set PIXELLAB_SECRET")
    client = pixellab.Client(secret=secret)
    enc = lambda im: Base64Image.from_pil_image(im).model_dump() if im is not None else None
    body = {
        "description": prompt,
        "image_size": {"width": int(size[0]), "height": int(size[1])},
        "no_background": no_background, "seed": int(seed),
        "style_strength": style_strength,
        "init_image": enc(init_image), "init_image_strength": int(init_image_strength),
        "style_image": enc(style_image),
        "color_image": enc(color_image),
    }
    r = requests.post(f"{client.base_url}/generate-image-bitforge",
                      headers=client.headers(), json=body, timeout=180)
    r.raise_for_status()
    data = r.json()
    b64img = (data.get("image") or {}).get("base64")
    if not b64img:
        raise RuntimeError(f"PixelLab returned no image: {data}")
    if "," in b64img:
        b64img = b64img.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(b64img))).convert("RGBA")

# ---- Retro Diffusion (RD-Plus + input palette) ----
def _rd_payload(prompt, w, h, style):
    return {"prompt": prompt, "width": w, "height": h, "model": style,
            "num_images": 1, "remove_bg": True}

def rd_icon(prompt, size, style="rd_plus__retro", palette_image=None, ref_image=None):
    import requests
    token = os.environ.get("RD_API_TOKEN")
    if not token:
        raise RuntimeError("set RD_API_TOKEN")
    body = _rd_payload(prompt, size[0], size[1], style)
    if palette_image is not None:
        body["palette_image"] = _b64_png(palette_image)
    if ref_image is not None:
        body["input_image"] = _b64_png(ref_image); body["strength"] = IMG2IMG_STRENGTH
    r = requests.post("https://api.retrodiffusion.ai/v1/inferences",
                      headers={"X-RD-Token": token}, json=body, timeout=120)
    r.raise_for_status()
    data = r.json()
    imgs = data.get("base64_images") or []
    if not imgs:
        raise RuntimeError(f"RD returned no images: {data}")
    return Image.open(io.BytesIO(base64.b64decode(imgs[0]))).convert("RGBA")
