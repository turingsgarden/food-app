import os
import base64
import requests
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

def gmail_send_email(to_email, subject, html_body, text_body):
    CLIENT_ID = os.getenv("GMAIL_CLIENT_ID")
    CLIENT_SECRET = os.getenv("GMAIL_CLIENT_SECRET")
    REFRESH_TOKEN = os.getenv("GMAIL_REFRESH_TOKEN")
    SENDER_EMAIL = os.getenv("SENDER_EMAIL")

    # 1. Get access token using refresh token
    token_url = "https://oauth2.googleapis.com/token"
    data = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "refresh_token": REFRESH_TOKEN,
        "grant_type": "refresh_token",
    }

    token_response = requests.post(token_url, data=data)
    token_json = token_response.json()
    access_token = token_json.get("access_token")

    if not access_token:
        print("❌ Failed to get access token:", token_json)
        return False

    # 2. Build message
    message = MIMEMultipart("alternative")
    message["To"] = to_email
    message["From"] = SENDER_EMAIL
    message["Subject"] = subject

    message.attach(MIMEText(text_body, "plain"))
    message.attach(MIMEText(html_body, "html"))

    raw_message = base64.urlsafe_b64encode(message.as_bytes()).decode()

    # 3. Send email using Gmail API
    gmail_url = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    payload = {"raw": raw_message}

    response = requests.post(gmail_url, headers=headers, json=payload)

    print("📨 Gmail API Response Status:", response.status_code)
    print("📨 Gmail API Response Body:", response.text)

    return response.status_code in [200, 202]
