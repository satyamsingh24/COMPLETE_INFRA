from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

SENDER = 'satyamsinghbhadoriya922@gmail.com'
PASSWORD = 'rhpzmsydgimrkxge'
RECEIVER = 'satyamsinghbhadoriya922@gmail.com'

def send_email(subject, body):
    msg = MIMEMultipart()
    msg['From'] = SENDER
    msg['To'] = RECEIVER
    msg['Subject'] = subject
    msg.attach(MIMEText(body, 'plain'))
    server = smtplib.SMTP('smtp.gmail.com', 587)
    server.starttls()
    server.login(SENDER, PASSWORD)
    server.sendmail(SENDER, RECEIVER, msg.as_string())
    server.quit()
    print(f"✅ Email sent: {subject}")

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers['Content-Length'])
        data = json.loads(self.rfile.read(length))
        
        alerts = data.get('alerts', [])
        for alert in alerts:
            name = alert.get('labels', {}).get('alertname', 'Unknown')
            status = alert.get('status', 'unknown').upper()
            summary = alert.get('annotations', {}).get('summary', '')
            
            subject = f"🚨 Grafana Alert: {name} - {status}"
            body = f"""
Alert Name  : {name}
Status      : {status}
Summary     : {summary}
Labels      : {alert.get('labels', {})}
Started     : {alert.get('startsAt', '')}
"""
            send_email(subject, body)
        
        self.send_response(200)
        self.end_headers()
    
    def log_message(self, format, *args):
        print(f"[Webhook] {args[0]} {args[1]}")

print("🚀 Webhook server starting on port 5001...")
HTTPServer(('0.0.0.0', 5001), WebhookHandler).serve_forever()
