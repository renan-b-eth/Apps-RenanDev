import os
from PIL import Image, ImageOps

# Configurações
BG_COLOR = "#006400"  # Seu verde escuro
INPUT_FILES = ["print1.png", "print2.png", "print3.png"]
OUTPUT_DIR = "google_play_assets"

# Dimensões Exatas exigidas/recomendadas pelo Google Play
TARGETS = {
    "Phone": (1080, 1920),       # 9:16 Standard
    "Tablet7": (1200, 1920),     # 7 inch aspect ratio
    "Tablet10": (1600, 2560),    # 10 inch aspect ratio
    "Chromebook": (1366, 768)    # Laptop (Landscape)
}

def generate_screenshots():
    # Cria pastas de saída
    for category in TARGETS.keys():
        path = os.path.join(OUTPUT_DIR, category)
        os.makedirs(path, exist_ok=True)

    print(f"🚀 Iniciando geração de assets...")

    for filename in INPUT_FILES:
        if not os.path.exists(filename):
            print(f"⚠️ Arquivo {filename} não encontrado. Pulei.")
            continue

        try:
            original = Image.open(filename).convert("RGBA")
            
            for category, size in TARGETS.items():
                target_w, target_h = size
                
                # Cria o fundo verde
                canvas = Image.new("RGB", size, BG_COLOR)
                
                # Se for Chromebook (paisagem), a lógica é diferente
                if category == "Chromebook":
                    # Redimensiona mantendo proporção para caber na altura
                    padding = int(target_h * 0.1) # 10% de margem
                    safe_h = target_h - (padding * 2)
                    ratio = safe_h / original.height
                    new_w = int(original.width * ratio)
                    new_h = int(original.height * ratio)
                    
                    resized = original.resize((new_w, new_h), Image.Resampling.LANCZOS)
                    
                    # Centraliza
                    x = (target_w - new_w) // 2
                    y = (target_h - new_h) // 2
                    canvas.paste(resized, (x, y), resized)

                else:
                    # Modo Retrato (Phone/Tablet)
                    # Deixa uma margem de 10% nas laterais
                    padding = int(target_w * 0.1)
                    safe_w = target_w - (padding * 2)
                    
                    # Calcula altura proporcional
                    ratio = safe_w / original.width
                    new_w = safe_w
                    new_h = int(original.height * ratio)
                    
                    resized = original.resize((new_w, new_h), Image.Resampling.LANCZOS)
                    
                    # Centraliza
                    x = (target_w - new_w) // 2
                    y = (target_h - new_h) // 2
                    
                    # Se ficar muito alto, corta o excesso ou alinha ao topo
                    if new_h > target_h:
                         y = 50 # Margem superior fixa se for muito comprido
                    
                    canvas.paste(resized, (x, y), resized)

                # Salva
                output_path = os.path.join(OUTPUT_DIR, category, f"processed_{filename}")
                canvas.save(output_path, "PNG")
                print(f"✅ Gerado: {category} -> {filename}")

        except Exception as e:
            print(f"❌ Erro ao processar {filename}: {e}")

    print(f"\n✨ Tudo pronto! Abra a pasta '{OUTPUT_DIR}' e arraste para o Google Play.")

if __name__ == "__main__":
    generate_screenshots()