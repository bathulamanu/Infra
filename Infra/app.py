from flask import Flask
import os
import psycopg2

app = Flask(__name__)

@app.route("/healthz")
def healthz():
    return "ok", 200

@app.route("/")
def index():
    db_host = os.getenv("DB_HOST")
    db_name = os.getenv("DB_NAME", "appdb")
    db_user = os.getenv("DB_USER")
    db_pass = os.getenv("DB_PASSWORD")
    db_port = os.getenv("DB_PORT", "5432")

    try:
        conn = psycopg2.connect(
            host=db_host,
            dbname=db_name,
            user=db_user,
            password=db_pass,
            port=db_port,
            connect_timeout=3
        )
        cur = conn.cursor()
        cur.execute("SELECT 'Hello Pi Credit'::text;")
        row = cur.fetchone()
        cur.close()
        conn.close()
        return f"{row[0]} 🎉"
    except Exception as e:
        return f"DB connection error: {e}", 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "5000")))
