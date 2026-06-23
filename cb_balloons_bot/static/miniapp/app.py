# app.py — отдает твои index.html, styles.css и app.js прямо из текущей папки
from flask import Flask, send_from_directory
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
app = Flask(__name__, static_folder=None)

@app.route("/")
def index():
    return send_from_directory(ROOT, "index.html")

@app.route("/<path:path>")
def serve_file(path):
    # позволит отдавать styles.css, app.js и любые будущие файлы
    return send_from_directory(ROOT, path)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
