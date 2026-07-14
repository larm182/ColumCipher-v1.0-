#!/usr/bin/env python
import random
import os
import json
import base64
from flask import Flask, request, jsonify
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import re
from urllib.request import urlopen
import socket
import uuid
import platform
from datetime import datetime

app = Flask(__name__)

profile = 100000
ip = 100000
ruta = os.getcwd() + "/output/"

# Crear directorio si no existe
os.makedirs(ruta, exist_ok=True)

def get_system_info():
    """Obtiene información del sistema"""
    try:
        hostname = socket.gethostname()
        system = platform.system()
        machine = platform.machine()
        processor = platform.processor()
        
        # Obtener información de red
        url = "http://ipinfo.io/json"
        response = urlopen(url)
        ip_data = json.load(response)
        
        # Información única de la máquina
        mac_address = ':'.join(re.findall('..', '%012x' % uuid.getnode()))
        
        system_info = {
            "hostname": hostname,
            "system": system,
            "machine": machine,
            "processor": processor,
            "mac_address": mac_address,
            "ip_info": ip_data
        }
        
        return system_info
    except Exception as e:
        return {"error": str(e)}

def generate_rsa_keypair():
    """Genera par de llaves RSA"""
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )
    
    public_key = private_key.public_key()
    
    # Serializar llaves
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    
    return private_pem, public_pem

def generate_aes_key():
    """Genera llave AES-256"""
    return os.urandom(32)  # 32 bytes = 256 bits

def save_key_info(profile_id, key_data, system_info, key_type="AES"):
    """Guarda la información de la llave y sistema en un archivo"""
    filename = f"key_profile_{profile_id}.json"
    filepath = os.path.join(ruta, filename)
    
    key_info = {
        "profile_id": profile_id,
        "key_type": key_type,
        "key_data": base64.b64encode(key_data).decode('utf-8'),
        "system_info": system_info,
        "timestamp": datetime.now().isoformat(),
        "key_size": len(key_data)
    }
    
    with open(filepath, 'w') as f:
        json.dump(key_info, f, indent=2)
    
    return filepath

@app.route("/")
def inicio():
    """Endpoint principal que genera y retorna llave"""
    global profile, ip
    
    ip += 1
    profile += 1
    
    try:
        # Obtener información del sistema
        system_info = get_system_info()
        
        # Guardar información de IP
        ip_filename = f"ip_{ip}.json"
        with open(os.path.join(ruta, ip_filename), 'w') as f:
            json.dump(system_info, f, indent=2)
        
        # Generar llave AES
        aes_key = generate_aes_key()
        
        # Guardar información de la llave con datos del sistema
        key_filepath = save_key_info(profile, aes_key, system_info, "AES-256")
        
        print(f"Llave guardada en: {key_filepath}")
        
        # Retornar llave AES en base64
        return base64.b64encode(aes_key).decode('utf-8')
        
    except Exception as e:
        return f"Error: {str(e)}", 500

@app.route("/simple-key", methods=["GET", "POST"])  # ACEPTA GET Y POST
def simple_key():
    """Endpoint simple que siempre funciona"""
    global profile
    profile += 1
    
    try:
        # Generar llave simple de 32 bytes (256 bits)
        key = os.urandom(32)
        
        # Información del sistema
        system_info = get_system_info()
        
        # Guardar
        key_filepath = save_key_info(profile, key, system_info, "AES-256-SIMPLE")
        
        return jsonify({
            "key": base64.b64encode(key).decode('utf-8'),
            "profile_id": profile,
            "message": "Llave generada exitosamente",
            "file_saved": key_filepath
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# 🔥 NUEVO ENDPOINT: Guardar llave completa desde la app
@app.route("/save-key", methods=["POST"])
def save_key():
    """Endpoint para guardar llaves completas desde la app móvil"""
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        # Extraer datos
        aes_key = data.get('aes_key')
        profile_id = data.get('profile_id')
        encrypted_path = data.get('encrypted_path')
        iv = data.get('iv')
        total_files = data.get('total_files')
        timestamp = data.get('timestamp')
        
        if not all([aes_key, profile_id, iv]):
            return jsonify({"error": "Missing required fields"}), 400
        
        # Crear archivo de llave completo
        key_info = {
            "profile_id": profile_id,
            "aes_key": aes_key,
            "iv": iv,
            "encrypted_path": encrypted_path,
            "total_files": total_files,
            "timestamp": timestamp,
            "device_info": data.get('device_info', {}),
            "key_type": "AES-256-MOBILE",
            "key_size": 32
        }
        
        # Guardar en archivo
        filename = f"mobile_key_{profile_id}.json"
        filepath = os.path.join(ruta, filename)
        
        with open(filepath, 'w') as f:
            json.dump(key_info, f, indent=2)
        
        print(f"✅ Llave móvil guardada: {filepath}")
        print(f"   Profile ID: {profile_id}")
        print(f"   Archivos: {total_files}")
        print(f"   Ruta: {encrypted_path}")
        print(f"   IV: {iv[:20]}...")
        
        return jsonify({
            "status": "success",
            "message": "Key saved successfully",
            "profile_id": profile_id,
            "file_path": filepath
        })
        
    except Exception as e:
        print(f"❌ Error saving mobile key: {e}")
        return jsonify({"error": str(e)}), 500

# 🔥 NUEVO ENDPOINT: Obtener llave por profile_id
@app.route("/get-key/<int:profile_id>")
def get_key(profile_id):
    """Endpoint para obtener una llave específica por profile_id"""
    try:
        # Buscar archivo por profile_id
        for filename in os.listdir(ruta):
            if f"mobile_key_{profile_id}" in filename and filename.endswith(".json"):
                filepath = os.path.join(ruta, filename)
                with open(filepath, 'r') as f:
                    key_info = json.load(f)
                return jsonify(key_info)
        
        return jsonify({"error": "Key not found"}), 404
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# 🔥 NUEVO ENDPOINT: Listar todas las llaves móviles
@app.route("/mobile-keys")
def list_mobile_keys():
    """Endpoint para listar todas las llaves de móviles"""
    try:
        keys = []
        for filename in os.listdir(ruta):
            if filename.startswith("mobile_key_") and filename.endswith(".json"):
                filepath = os.path.join(ruta, filename)
                with open(filepath, 'r') as f:
                    key_info = json.load(f)
                
                safe_info = {
                    "profile_id": key_info.get("profile_id"),
                    "encrypted_path": key_info.get("encrypted_path"),
                    "total_files": key_info.get("total_files"),
                    "timestamp": key_info.get("timestamp"),
                    "filename": filename
                }
                keys.append(safe_info)
        
        return jsonify({"mobile_keys": keys, "total": len(keys)})
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/rsa-key")
def generate_rsa_key():
    """Endpoint para generar par de llaves RSA"""
    global profile
    
    profile += 1
    
    try:
        # Obtener información del sistema
        system_info = get_system_info()
        
        # Generar par de llaves RSA
        private_key, public_key = generate_rsa_keypair()
        
        # Guardar ambas llaves con información del sistema
        private_key_filepath = save_key_info(f"{profile}_private", private_key, system_info, "RSA-PRIVATE")
        public_key_filepath = save_key_info(f"{profile}_public", public_key, system_info, "RSA-PUBLIC")
        
        print(f"Llaves RSA guardadas: {private_key_filepath}, {public_key_filepath}")
        
        # Retornar llave pública
        return public_key.decode('utf-8')
        
    except Exception as e:
        return f"Error: {str(e)}", 500

@app.route("/keys/<int:profile_id>")
def get_key_info(profile_id):
    """Endpoint para obtener información de una llave específica"""
    try:
        # Buscar archivo por patrón
        for filename in os.listdir(ruta):
            if f"key_profile_{profile_id}" in filename and filename.endswith(".json"):
                filepath = os.path.join(ruta, filename)
                with open(filepath, 'r') as f:
                    key_info = json.load(f)
                return jsonify(key_info)
        
        return jsonify({"error": "Key profile not found"}), 404
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/keys")
def list_all_keys():
    """Endpoint para listar todas las llaves generadas"""
    try:
        keys = []
        for filename in os.listdir(ruta):
            if filename.startswith("key_profile_") and filename.endswith(".json"):
                filepath = os.path.join(ruta, filename)
                with open(filepath, 'r') as f:
                    key_info = json.load(f)
                
                # No mostrar la llave completa por seguridad
                safe_info = {
                    "profile_id": key_info.get("profile_id"),
                    "key_type": key_info.get("key_type"),
                    "timestamp": key_info.get("timestamp"),
                    "system_info": key_info.get("system_info", {}).get("hostname", "Unknown"),
                    "filename": filename
                }
                keys.append(safe_info)
        
        return jsonify({"keys": keys, "total": len(keys)})
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/status")
def status():
    """Endpoint para ver el estado del servidor"""
    try:
        total_keys = len([f for f in os.listdir(ruta) if f.startswith("key_profile_")])
        total_ips = len([f for f in os.listdir(ruta) if f.startswith("ip_")])
        total_mobile_keys = len([f for f in os.listdir(ruta) if f.startswith("mobile_key_")])
        
        return jsonify({
            "status": "running",
            "total_keys_generated": total_keys,
            "total_mobile_keys": total_mobile_keys,
            "total_ips_stored": total_ips,
            "output_directory": ruta,
            "next_profile_id": profile + 1,
            "next_ip_id": ip + 1
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    print(f"=== Servidor de Generación de Llaves ===")
    print(f"Directorio de salida: {ruta}")
    print(f"Endpoints disponibles:")
    print(f"  GET  /          - Generar llave AES y retornarla")
    print(f"  GET/POST /simple-key - Generar llave simple")
    print(f"  POST /save-key  - 🔥 Guardar llave desde móvil")
    print(f"  GET  /get-key/<id> - 🔥 Obtener llave móvil")
    print(f"  GET  /mobile-keys - 🔥 Listar llaves móviles")
    print(f"  GET  /rsa-key   - Generar llaves RSA")
    print(f"  GET  /keys      - Listar llaves")
    print(f"  GET  /status    - Estado del servidor")
    print("=" * 50)
    
    app.run(host='0.0.0.0', port=5000, debug=True)