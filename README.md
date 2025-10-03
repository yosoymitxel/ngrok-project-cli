# 🚀 Ngrok Project CLI

## Descripción

`ngrok_project` es un script de shell diseñado para simplificar el proceso de desarrollo y pruebas locales. Ejecuta automáticamente la subida de contenedores Docker (usando `docker compose` o `Dockerfile`) y establece un **túnel inverso de Ngrok** en el puerto configurado, exponiendo tu proyecto al internet público.

Incluye lógica de **espera inteligente** y maneja los permisos de Ngrok (Snap/SUDO) de forma robusta.

## Uso

Ejecuta el script **dentro del directorio raíz** de tu proyecto Docker.

| Comando | Descripción |
| :--- | :--- |
| `sudo ngrok_project start` | Levanta el servicio Docker (si no está activo), inicia Ngrok, espera la URL pública y la muestra en la consola. |
| `sudo ngrok_project stop` | Detiene el túnel de Ngrok y baja todos los servicios Docker (`docker compose down` o `docker stop/rm`). |

## ⚙️ Configuración (Archivos)

El script utiliza variables para su funcionamiento, priorizando el puerto de tu entorno:

1.  **Puerto del Proyecto:** El script intenta leer el puerto externo del host desde la variable `WEB_PORT` en el archivo local **`.env`**. Si no se encuentra, usa el valor por defecto (`8080`).
2.  **Tiempo de Espera:** Las variables internas `SLEEP_DOCKER_INIT` (inicio de Docker) y `MAX_NGROK_WAIT` (espera de URL) son configurables dentro del script si tu entorno es especialmente lento.

## ⚠️ Requisitos

* **Docker** y **Docker Compose** (o `docker compose` CLI) instalados y funcionales.
* **Ngrok** instalado vía Snap (`/snap/bin/ngrok`).
* **Authtoken de Ngrok** configurado previamente en tu usuario.
