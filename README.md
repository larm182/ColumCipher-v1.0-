


# 🔒 ColumCipher v1.0

<img width="1413" height="715" alt="image" src="https://github.com/user-attachments/assets/7fb70bac-c57d-4b23-bb3c-2fd9a9821e29" />


**Sistema de cifrado y descifrado de archivos con gestión remota de llaves.**

ColumCipher protege archivos con **AES-256** bajo un principio claro: **la llave nunca se queda en el dispositivo**. Las llaves y sus vectores de inicialización (IV) se generan localmente, se aplican a los archivos y se envían a un servidor central. El equipo se queda solo con los archivos cifrados; para recuperarlos hay que solicitar las llaves al servidor.

> Creado por **Larm182** · GuajiraSec

---

## 📑 Tabla de contenido

- [Características](#-características)
- [Cómo funciona](#-cómo-funciona)
- [Requisitos](#-requisitos)
- [Instalación](#-instalación)
- [Uso paso a paso](#-uso-paso-a-paso)
- [Estructura del proyecto](#-estructura-del-proyecto)
- [Advertencias de seguridad](#-advertencias-de-seguridad)
- [Roadmap](#-roadmap)

---

## ✨ Características

- Cifrado de múltiples archivos con **AES-256**.
- **Las llaves NO se almacenan en el dispositivo.**
- Gestión centralizada de llaves desde un servidor.
- Recuperación controlada de llaves para el descifrado.
- Identificación de cada operación mediante un **Profile ID**.

---

## ⚙️ Cómo funciona

El sistema tiene tres piezas que se comunican por red:

| Componente | Rol |
|---|---|
| **Encriptador** (app móvil) | Genera la llave, cifra los archivos y publica la llave en el servidor. |
| **Servidor de llaves** (Python) | Almacena y sirve las llaves e IV, indexados por Profile ID. |
| **Desencriptador** (app móvil) | Recupera las llaves del servidor y restaura los archivos. |

El material que se guarda en el servidor viaja como JSON (llave e IV en Base64):

```json
{
  "profile_id": 100001,
  "aes_key": "qT0vVdMSj3ghl2O2+fEMGhfqi3eXtFKGwuBI8zPCr2E=",
  "iv": "xCy973r9T9uAB6t9M4W8QQ==",
  "encrypted_path": "/storage/emulated/0/Prueba",
  "total_files": 4,
  "key_type": "AES-256-MOBILE",
  "key_size": 32
}
```

---

<img width="682" height="730" alt="image" src="https://github.com/user-attachments/assets/f4014769-483b-4ca0-ba30-3487493d39f5" />


## 📋 Requisitos

**Servidor**
- Python 3.8 o superior
- Dependencias listadas en `requirements.txt`

**Apps móviles**
- Dispositivo Android
- Encriptador y desencriptador (APK) instalados
- El teléfono y el servidor deben estar en la **misma red local**

---

## 🚀 Instalación

### 1. Clonar el repositorio
```bash
git clone https://github.com/<tu-usuario>/ColumCipher.git
cd ColumCipher
```

### 2. Instalar dependencias del servidor
```bash
pip install -r requirements.txt
```

### 3. Iniciar el servidor
```bash
python server.py
```

El servidor quedará escuchando en tu IP local, por ejemplo: http://192.168.1.4:5000

> Anota esta URL: la necesitarás en ambas apps.

### 4. Instalar las apps
Instala en tu dispositivo Android:
- `Encriptador.apk`
- `Desencriptador.apk`

---

## 📱 Uso paso a paso

### 🔴 Cifrar una carpeta
1. Abre la app **Encriptador**.
2. Ingresa la **URL del servidor** (ej. `http://192.168.1.4:5000`).
3. Indica la **ruta de la carpeta** a proteger (ej. `/storage/emulated/0/Prueba`).
4. Pulsa **ENCRIPTAR CARPETA**.
5. Al terminar verás el **Profile ID** de la operación. **Guárdalo**: lo necesitas para descifrar.

> Resultado: cada archivo pasa a tener extensión `.enc`, los originales se eliminan y la llave se envía al servidor.

### 🟢 Descifrar una carpeta
1. Abre la app **Desencriptador**.
2. Ingresa la misma **URL del servidor**.
3. Escribe el **Profile ID** y pulsa **Buscar** (o **Cargar Todas las Llaves**).
4. Verifica la llave cargada (ruta, número de archivos, IV).
5. Pulsa **DESENCRIPTAR CARPETA**.

> Resultado: los archivos vuelven a su estado original.

---

## 📂 Estructura del proyecto

ColumCipher/
├── server/
│   ├── server.py            # Servidor de gestión de llaves
│   └── requirements.txt     # Dependencias de Python
├── apps/
│   ├── Encriptador.apk      # App para cifrar
│   └── Desencriptador.apk   # App para descifrar
├── docs/                    # Documentación e imágenes
└── README.md

---
## Link para descargar las aplicaciones: https://drive.google.com/file/d/1wtO9VpTmIASsj3oyX93zIMcvENTZxg_r/view?usp=sharing


## ⚠️ Advertencias de seguridad

- **El cifrado es destructivo:** los archivos originales se eliminan tras cifrar. Asegúrate de poder recuperar la llave antes de continuar.
- **Sin servidor no hay descifrado:** si el servidor no está disponible o se pierde el Profile ID, los datos permanecen inaccesibles.
- **El servidor es un punto único de fallo:** respáldalo y protégelo adecuadamente.
- **Uso responsable:** esta herramienta es para proteger datos propios o con autorización. El autor no se responsabiliza por usos indebidos.

> ⚠️ **Estado actual:** proyecto en desarrollo/pruebas. En esta versión el transporte de llaves aún no está cifrado (HTTP). No usar en producción sin aplicar el endurecimiento del roadmap.

---

## 🛣️ Roadmap

- [ ] Transporte cifrado (HTTPS/TLS) con *certificate pinning*
- [ ] Autenticación y autorización en el servidor
- [ ] Cifrado de llaves en reposo (KMS/HSM)
- [ ] Integridad autenticada con **AES-256-GCM**
- [ ] Registro de auditoría y límites de tasa
- [ ] IV/nonce único por archivo: generar un vector nuevo con un CSPRNG para cada archivo y anteponerlo al cifrado (IV || ciphertext). Reutilizar IV con la misma llave rompe la semántica de CBC y es crítico en GCM.

---

*Seguimos construyendo y probando seguridad desde la práctica. 🚀*
**— Larm182 / GuajiraSec**

