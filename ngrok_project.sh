#!/bin/bash
# Script de Control de Túnel Ngrok con Detección de Directorio (Docker Compose/Dockerfile)
# ----------------------------------------------
# 1. Variables de Configuración (Ajustables)
# ----------------------------------------------
PORT_PROJECT="8080"
NGROK_TOKEN="YOUR_API_KEY" # ¡Tu clave!
URL_PUBLICA="YOUR_PUBLIC_URL"

# Tiempos de espera
SLEEP_DOCKER_INIT=5  # Tiempo de espera inicial para que Docker suba (antes de la espera inteligente)
MAX_NGROK_WAIT=60    # Tiempo máximo de espera (en segundos) para que Ngrok genere la URL

# ----------------------------------------------
# 2. Variables Fijas
# ----------------------------------------------
LOG_FILE="/tmp/ngrok_project.log"
PID_FILE="/tmp/ngrok_project.pid"
NGROK_BIN="/snap/bin/ngrok" # Ruta de Ngrok instalado por Snap

# ----------------------------------------------
# 3. Funciones de Detección y Comprobación
# ----------------------------------------------

# Comprueba dependencias básicas (Docker y Ngrok)
check_dependencies() {
    if ! command -v docker-compose &> /dev/null && ! command -v docker compose &> /dev/null; then
        echo "❌ Error: Docker Compose no está instalado o no es accesible."
        exit 1
    fi
    if ! command -v "$NGROK_BIN" &> /dev/null; then
        echo "❌ Error: Ngrok no se encuentra en $NGROK_BIN. Instala con 'sudo snap install ngrok'."
        exit 1
    fi
    # Configurar el Authtoken
    ngrok config add-authtoken "$NGROK_TOKEN" 2>/dev/null || true
}

# Detecta los archivos de configuración en el directorio actual
detect_project() {
    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        DOCKER_MODE="compose"
        echo "🐳 Modo: Docker Compose detectado."
    elif [ -f "Dockerfile" ]; then
        DOCKER_MODE="build"
        echo "🐳 Modo: Dockerfile detectado."
    else
        echo "❌ Error: No se encontró 'docker-compose.yml' ni 'Dockerfile' en el directorio actual."
        exit 1
    fi
    
    if [ -f ".env" ]; then
        echo "📄 Archivo .env detectado y será usado."
    fi
}

# ----------------------------------------------
# 4. Control de Servicios
# ----------------------------------------------

manage_docker_web() {
    ACTION=$1
    
    if [ "$ACTION" == "start" ]; then
        echo "--- 🐳 Iniciando Proyecto Docker en segundo plano ---"
        
        if [ "$DOCKER_MODE" == "compose" ]; then
            # Usa Docker Compose para levantar el proyecto
            sudo docker compose up -d --build
        else
            # Modo Dockerfile simple: Construye y levanta el contenedor en el puerto 8080
            PROJECT_NAME=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')
            CONTAINER_NAME="${PROJECT_NAME}_web"
            
            # 1. Comprobar si la imagen ya existe para evitar reconstrucciones
            if ! sudo docker image inspect $PROJECT_NAME &> /dev/null; then
                echo "🔨 Imagen '$PROJECT_NAME' no encontrada. Construyendo..."
                sudo docker build -t $PROJECT_NAME .
                if [ $? -ne 0 ]; then
                    echo "❌ Error al construir la imagen Docker."
                    exit 1
                fi
            else
                echo "✅ Imagen '$PROJECT_NAME' encontrada en caché. Saltando construcción."
            fi
            
            # 2. Detener y eliminar cualquier instancia anterior
            sudo docker stop $CONTAINER_NAME 2>/dev/null
            sudo docker rm $CONTAINER_NAME 2>/dev/null
            
            # 3. Iniciar el nuevo contenedor, mapeando 8080 al puerto interno 80
            sudo docker run -d --name $CONTAINER_NAME -p $PORT_PROJECT:80 $PROJECT_NAME
        fi

        if [ $? -eq 0 ]; then
            echo "✅ Servicio Docker levantado. Esperando $SLEEP_DOCKER_INIT segundos para inicio..."
        else
            echo "❌ Error al iniciar el servicio Docker."
            exit 1
        fi
        sleep $SLEEP_DOCKER_INIT 

    elif [ "$ACTION" == "stop" ]; then
        echo "--- 🗑️ Deteniendo Servicio Docker ---"
        
        if [ "$DOCKER_MODE" == "compose" ]; then
            sudo docker compose down
        else
            PROJECT_NAME=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-')
            CONTAINER_NAME="${PROJECT_NAME}_web"
            sudo docker stop $CONTAINER_NAME 2>/dev/null
            sudo docker rm $CONTAINER_NAME 2>/dev/null
        fi
        echo "✅ Servicio Docker detenido."
    fi
}

start_tunnel() {
    detect_project
    check_dependencies
    
    manage_docker_web start # Inicia el Docker antes del túnel
    
    echo -e "\n--- 🚀 Iniciando Túnel Inverso en puerto $PORT_PROJECT ---"
    
    # Limpia cualquier Ngrok previo
    # pkill ngrok 2>/dev/null || true
    rm -f $LOG_FILE $PID_FILE

    # Inicia Ngrok en background
    sudo -E nohup "$NGROK_BIN" http $PORT_PROJECT --log=stdout &> $LOG_FILE &
    NGROK_PID=$!
    echo "$NGROK_PID" > $PID_FILE
    
    # Bucle de Espera Inteligente (¡El poder!)
    MAX_TRIES=$MAX_NGROK_WAIT
    TRIES=0
    

    echo -e "\n🕵️‍ Buscando URL de Ngrok... ${URL_PUBLICA}"
    echo "⌛ Esperando URL de Ngrok (Máximo ${MAX_NGROK_WAIT}s)..."
    while [ -z "$URL_PUBLICA" ] && [ $TRIES -lt $MAX_TRIES ]; do
        sleep 1
        URL_PUBLICA=$(grep -o "url=[^ ]*" $LOG_FILE | tail -n 1 | cut -d "=" -f 2)
        TRIES=$((TRIES + 1))
    done
    
    if [ -z "$URL_PUBLICA" ]; then
        echo -e "\n❌ Error Crítico: Ngrok falló o no se pudo obtener la URL en ${MAX_NGROK_WAIT} segundos."
        manage_docker_web stop 
        exit 1
    else
        echo -e "\n✅ Túnel establecido con éxito."
        echo "---------------------------------------------------------"
        echo "🔥 ¡Proyecto expuesto en línea! 🔥"
        echo "   $URL_PUBLICA"
        echo "---------------------------------------------------------"
        echo "Para detenerlo: sudo ngrok_project stop"
        echo "Para detenerlo forzadamente: sudo pkill -9 ngrok 2>/dev/null || true; ps aux | grep -i 'ngrok'"
    fi
}

stop_tunnel() {
    detect_project
    echo "--- 🛑 Deteniendo Túnel y Limpieza ---"
    
    # Detener Docker
    manage_docker_web stop 
    
    # Detener Ngrok
    pkill ngrok 2>/dev/null
    rm -f $PID_FILE $LOG_FILE
    echo "✅ Ngrok detenido y limpieza completa."
}

# ----------------------------------------------
# 5. Ejecución Principal
# ----------------------------------------------

case "$1" in
    start)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    *)
        echo "---------------------------------------------------------"
        echo " Herramienta Ngrok Project (Puerto $PORT_PROJECT)"
        echo "---------------------------------------------------------"
        echo "Uso: sudo ngrok_project [start|stop]"
        echo "  (Ejecutar DENTRO de la carpeta de tu proyecto Docker.)"
        ;;
esac
