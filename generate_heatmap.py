import os
TOKEN = os.environ.get("TOKEN")
if not TOKEN:
    raise ValueError("Le token [ main.yml > env: TOKEN=[...] ] n'a pas été trouvé")
import requests
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import matplotlib.colors as mcolors
from datetime import datetime, timedelta
from collections import Counter
import numpy as np

# === CONFIG ===
GITLAB_URL = "https://gitlab.univ-artois.fr"
USERNAME = "malik_babahamou"

headers = {"PRIVATE-TOKEN": TOKEN}

# === Trouver l'utilisateur ===
user_resp = requests.get(f"{GITLAB_URL}/api/v4/users?username={USERNAME}", headers=headers)
users = user_resp.json()
if not users:
    raise ValueError("Impossible de trouver l'utilisateur.")
user_id = users[0]["id"]

# === Récupérer les événements push ===
events = []
page = 1
while True:
    r = requests.get(
        f"{GITLAB_URL}/api/v4/users/{user_id}/events",
        headers=headers,
        params={"action": "pushed", "per_page": 100, "page": page}
    )
    data = r.json()
    if not data:
        break
    events.extend(data)
    page += 1

print(f"✅ {len(events)} événements trouvés")

# === Comptage par jour ===
dates = [datetime.strptime(e["created_at"][:10], "%Y-%m-%d").date() for e in events]
counter = Counter(dates)

# === Créer une grille sur 1 an ===
today = datetime.today().date()
start_date = today - timedelta(days=250)
all_days = [start_date + timedelta(days=i) for i in range(251)]

weeks = (len(all_days) + 6) // 7
heatmap = np.zeros((7, weeks), dtype=int)

for i, day in enumerate(all_days):
    week = i // 7
    weekday = day.weekday()
    heatmap[weekday, week] = counter.get(day, 0)

# === Définir les tranches de couleur et convertir en RGB float ===
def hex_to_rgb(hex_color):
    h = hex_color.lstrip('#')
    return tuple(int(h[i:i+2], 16)/255 for i in (0, 2, 4))

def get_color(val):
    if val == 0:
        return hex_to_rgb("#222222")  # noir
    elif 1 <= val <= 10:
        return hex_to_rgb("#b074c8")  # violet clair
    elif 11 <= val <= 20:
        return hex_to_rgb("#a44fc6")  # violet moyen
    elif 21 <= val <= 30:
        return hex_to_rgb("#a43dd0")  # violet foncé
    else:  # 31+
        return hex_to_rgb("#9b0bd4")  # violet très foncé

# Créer la matrice RGB
color_matrix = np.zeros((7, weeks, 3))
for i in range(7):
    for j in range(weeks):
        color_matrix[i, j] = get_color(heatmap[i, j])

# === Affichage ===
fig, ax = plt.subplots(figsize=(weeks/3, 3))
ax.imshow(color_matrix, aspect='equal')

# Cadrillage style GitHub
for i in range(7):
    for j in range(weeks):
        rect = patches.Rectangle(
            (j-0.5, i-0.5), 1, 1,
            linewidth=0.5, edgecolor="#444444", facecolor='none'
        )
        ax.add_patch(rect)

# Style dark
ax.set_facecolor("#222222")
fig.patch.set_facecolor("#222222")
ax.set_yticks(range(7))
ax.set_yticklabels(["L", "M", "M", "J", "V", "S", "D"], color="#f0f0f0")
ax.set_xticks([])

# Date de mise à jour
date_maj = datetime.now().strftime("%d / %m / %y")
ax.set_title(f"Activité GitLab de {USERNAME} (mis à jour le : {date_maj})", color="#f0f0f0")

# === Ajouter un tag invisible (force un changement unique chaque jour) ===
timestamp = datetime.now().isoformat()
ax.text(-1, -1, f"generated={timestamp}", fontsize=1, color="#222222")  # invisible

plt.tight_layout()
plt.savefig("gitlab_heatmap.svg", facecolor="#222222", bbox_inches="tight")
plt.close(fig)

print(f"Heatmap gitlab générée : gitlab_heatmap.svg ({timestamp})")