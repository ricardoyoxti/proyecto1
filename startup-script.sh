#!/bin/bash
set -e

# Redirigir salida a log para debugging
exec > >(tee /var/log/startup-script.log | logger -t startup-script -s 2>/dev/console) 2>&1

# Colores para logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[$(date +'%F %T')] $1${NC}"; }
error()   { echo -e "${RED}[$(date +'%F %T')] ERROR: $1${NC}"; }
info()    { echo -e "${BLUE}[$(date +'%F %T')] INFO: $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date +'%F %T')] WARN: $1${NC}"; }

# ➕ Obtener metadatos desde GCP con mejor manejo de errores
log "🔍 Obteniendo metadatos de GCP..."
INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/instance-name" -H "Metadata-Flavor: Google" 2>/dev/null || echo "odoo-instance")
DEPLOYMENT_TIME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/deployment-time" -H "Metadata-Flavor: Google" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
GITHUB_ACTOR=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github-actor" -H "Metadata-Flavor: Google" 2>/dev/null || echo "unknown")

# Variables de configuración
ODOO_VERSION="18.0"
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_CONFIG="/etc/odoo/odoo.conf"
ODOO_PORT="8072"
POSTGRES_USER="odoo"
POSTGRES_DB="odoo"
POSTGRES_PASSWORD="odoo123"

log "🚀 Iniciando instalación de Odoo 18 Community"
info "📋 Instancia: $INSTANCE_NAME"
info "📅 Despliegue: $DEPLOYMENT_TIME"
info "👤 GitHub actor: $GITHUB_ACTOR"

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Función para verificar conectividad a internet
check_internet() {
    if ! curl -s --max-time 10 http://www.google.com > /dev/null; then
        error "No hay conectividad a internet"
        exit 1
    fi
}

# Verificar conectividad
log "🌐 Verificando conectividad a internet..."
check_internet

# Actualización del sistema
log "📦 Actualizando sistema..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y

# Instalar dependencias completas del sistema incluyendo OpenSSL
log "🔧 Instalando dependencias del sistema..."
apt-get install -y \
    wget git curl unzip python3 python3-venv python3-pip python3-dev \
    libxml2-dev libxslt1-dev libevent-dev libsasl2-dev libldap2-dev libpq-dev \
    libjpeg-dev libpng-dev libfreetype6-dev liblcms2-dev libwebp-dev libharfbuzz-dev \
    libfribidi-dev libxcb1-dev libfontconfig1 xfonts-base xfonts-75dpi gcc g++ make \
    build-essential libssl-dev libffi-dev libbz2-dev libreadline-dev libsqlite3-dev \
    libncurses5-dev libncursesw5-dev xz-utils tk-dev libgdbm-dev libc6-dev \
    libnss3-dev libpython3-dev python3-wheel python3-setuptools ca-certificates \
    librust-openssl-dev pkg-config software-properties-common lsb-release \
    openssl libssl3 libcrypto++8

# Verificar instalación de OpenSSL
log "🔐 Verificando instalación de OpenSSL..."
if command_exists openssl; then
    OPENSSL_VERSION=$(openssl version)
    log "✅ OpenSSL instalado: $OPENSSL_VERSION"
else
    error "OpenSSL no se instaló correctamente"
    exit 1
fi

# Instalar PostgreSQL con mejor configuración
log "🐘 Instalando PostgreSQL..."
apt-get install -y postgresql postgresql-contrib postgresql-server-dev-all

# Configurar PostgreSQL para mejor rendimiento
log "⚙️ Configurando PostgreSQL..."
PG_VERSION=$(pg_config --version | awk '{print $2}' | sed 's/\..*//')
PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"

if [ -f "$PG_CONF" ]; then
    # Backup de configuración original
    cp "$PG_CONF" "$PG_CONF.backup"
    
    # Optimizaciones básicas para Odoo
    sed -i "s/#max_connections = 100/max_connections = 200/" "$PG_CONF"
    sed -i "s/#shared_buffers = 128MB/shared_buffers = 256MB/" "$PG_CONF"
    sed -i "s/#effective_cache_size = 4GB/effective_cache_size = 1GB/" "$PG_CONF"
    sed -i "s/#maintenance_work_mem = 64MB/maintenance_work_mem = 128MB/" "$PG_CONF"
    sed -i "s/#work_mem = 4MB/work_mem = 8MB/" "$PG_CONF"
fi

systemctl enable postgresql
systemctl start postgresql

# Validar PostgreSQL con reintentos
log "🔍 Verificando estado de PostgreSQL..."
for i in {1..5}; do
    if systemctl is-active --quiet postgresql; then
        log "✅ PostgreSQL está ejecutándose"
        break
    fi
    warn "PostgreSQL no está listo, esperando... (intento $i/5)"
    sleep 5
    if [ $i -eq 5 ]; then
        error "PostgreSQL no pudo iniciarse"
        systemctl status postgresql --no-pager
        exit 1
    fi
done

# Crear usuario y base de datos en PostgreSQL con mejor manejo
log "🗄️ Configurando PostgreSQL..."
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = '$POSTGRES_USER'" | grep -q 1 || {
    sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH CREATEDB PASSWORD '$POSTGRES_PASSWORD';"
    log "✅ Usuario PostgreSQL creado: $POSTGRES_USER"
}

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'" | grep -q 1 || {
    sudo -u postgres createdb -O $POSTGRES_USER $POSTGRES_DB
    log "✅ Base de datos creada: $POSTGRES_DB"
}

# Crear usuario del sistema Odoo
log "👤 Creando usuario del sistema Odoo..."
if ! id "$ODOO_USER" &>/dev/null; then
    adduser --system --quiet --home=$ODOO_HOME --group $ODOO_USER
    log "✅ Usuario del sistema creado: $ODOO_USER"
else
    info "Usuario $ODOO_USER ya existe"
fi

# Instalar wkhtmltopdf con mejor detección de versión
log "📄 Instalando wkhtmltopdf..."
cd /tmp
UBUNTU_VERSION=$(lsb_release -rs)
WKHTMLTOPDF_URL=""

case "$UBUNTU_VERSION" in
    "22.04")
        WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
        ;;
    "20.04")
        WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.focal_amd64.deb"
        ;;
    "24.04")
        WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.noble_amd64.deb"
        ;;
    *)
        warn "Versión de Ubuntu no reconocida: $UBUNTU_VERSION, usando focal como fallback"
        WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.focal_amd64.deb"
        ;;
esac

WKHTMLTOPDF_FILE=$(basename "$WKHTMLTOPDF_URL")
if [ ! -f "$WKHTMLTOPDF_FILE" ]; then
    wget -q "$WKHTMLTOPDF_URL" || {
        error "No se pudo descargar wkhtmltopdf"
        exit 1
    }
fi

dpkg -i "$WKHTMLTOPDF_FILE" || apt-get install -f -y
rm -f "$WKHTMLTOPDF_FILE"

# Verificar instalación de wkhtmltopdf
if command_exists wkhtmltopdf; then
    log "✅ wkhtmltopdf instalado correctamente"
else
    error "wkhtmltopdf no se instaló correctamente"
    exit 1
fi

# Clonar Odoo con mejor manejo
log "📥 Clonando Odoo $ODOO_VERSION..."
if [ -d "$ODOO_HOME" ]; then
    warn "Directorio $ODOO_HOME existe, eliminando..."
    rm -rf "$ODOO_HOME"
fi

git clone https://github.com/odoo/odoo --depth 1 --branch "$ODOO_VERSION" "$ODOO_HOME" || {
    error "No se pudo clonar Odoo"
    exit 1
}

chown -R $ODOO_USER:$ODOO_USER "$ODOO_HOME"

# Validaciones importantes
if [ ! -f "$ODOO_HOME/odoo-bin" ]; then
    error "No se encontró odoo-bin en $ODOO_HOME"
    ls -la "$ODOO_HOME/"
    exit 1
fi

if [ ! -f "$ODOO_HOME/requirements.txt" ]; then
    error "No se encontró requirements.txt en $ODOO_HOME"
    ls -la "$ODOO_HOME/"
    exit 1
fi

chmod +x "$ODOO_HOME/odoo-bin"
log "✅ Odoo clonado y configurado"

# Crear entorno virtual con mejor configuración
log "🐍 Creando entorno virtual Python..."
sudo -u $ODOO_USER python3 -m venv "$ODOO_HOME/venv"
chown -R $ODOO_USER:$ODOO_USER "$ODOO_HOME/venv"

# Actualizar pip, setuptools y wheel
log "📦 Actualizando herramientas de Python..."
sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/pip" install --upgrade pip setuptools wheel

# Instalar dependencias críticas primero
log "🔐 Instalando dependencias de OpenSSL y criptografía..."
sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/pip" install --upgrade \
    pyOpenSSL \
    cryptography \
    cffi

# Instalar psycopg2-binary
log "🐘 Instalando psycopg2-binary..."
sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/pip" install psycopg2-binary

# Instalar dependencias de Python con mejor manejo de errores
log "📦 Instalando dependencias Python..."
if ! sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/pip" install \
    --no-cache-dir \
    --timeout 300 \
    --retries 3 \
    -r "$ODOO_HOME/requirements.txt"; then
    
    error "Falló la instalación de dependencias Python estándar"
    info "Intentando instalación alternativa con versiones específicas..."
    
    # Lista de dependencias críticas con versiones compatibles
    CRITICAL_DEPS=(
        "Babel>=2.6.0"
        "chardet"
        "cryptography>=3.4.8"
        "pyOpenSSL>=22.0.0"
        "decorator"
        "docutils"
        "freezegun"
        "gevent"
        "greenlet"
        "idna"
        "Jinja2"
        "libsass"
        "lxml"
        "MarkupSafe"
        "num2words"
        "ofxparse"
        "passlib"
        "Pillow"
        "polib"
        "psutil"
        "pydot"
        "pyparsing"
        "PyPDF2"
        "pyserial"
        "python-dateutil"
        "python-stdnum"
        "pytz"
        "pyusb"
        "qrcode"
        "reportlab"
        "requests"
        "urllib3"
        "vobject"
        "Werkzeug"
        "xlrd"
        "XlsxWriter"
        "xlwt"
        "zeep"
        "rjsmin"
    )
    
    for dep in "${CRITICAL_DEPS[@]}"; do
        log "Instalando $dep..."
        sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/pip" install "$dep" || warn "Falló la instalación de $dep"
    done

    # Instalar lxml_html_clean si no está en requirements.txt
    log "📦 Instalando lxml_html_clean..."
    sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/pip" install lxml_html_clean || warn "Falló la instalación de lxml_html_clean"

fi

# Verificar instalación de OpenSSL en Python
log "🔍 Verificando instalación de OpenSSL en Python..."
if sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/python" -c "import OpenSSL; print('OpenSSL version:', OpenSSL.__version__)" 2>/dev/null; then
    log "✅ pyOpenSSL instalado correctamente"
else
    warn "Problema con pyOpenSSL, reintentando instalación..."
    sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/pip" install --force-reinstall pyOpenSSL cryptography
fi

# Verificar instalación de Python
log "🔍 Verificando instalación de Python..."
sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/python" -c "import odoo" 2>/dev/null || {
    warn "No se puede importar odoo directamente, pero continuando..."
}

# Configurar paths de addons mejorado
log "📁 Configurando paths de addons..."
ADDONS_PATH="$ODOO_HOME/addons"
if [ -d "$ODOO_HOME/odoo/addons" ]; then
    ADDONS_PATH="$ODOO_HOME/addons,$ODOO_HOME/odoo/addons"
fi

# Crear directorios necesarios
log "📁 Creando directorios de configuración..."
mkdir -p /etc/odoo /var/log/odoo /var/lib/odoo
chown -R $ODOO_USER:$ODOO_USER /var/log/odoo /var/lib/odoo

# Crear configuración mejorada
log "⚙️ Configurando Odoo..."
cat > "$ODOO_CONFIG" << EOF
[options]
# Configuración básica
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = $POSTGRES_USER
db_password = $POSTGRES_PASSWORD
db_name = False
addons_path = $ADDONS_PATH

# Logging
logfile = /var/log/odoo/odoo.log
log_level = info
log_db = False
log_handler = :INFO
log_db_level = warning

# HTTP
xmlrpc_port = $ODOO_PORT
xmlrpc_interface = 
longpolling_port = 8072

# Multiprocessing
workers = 0
max_cron_threads = 1

# Memory limits
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200

# Data directory
data_dir = /var/lib/odoo

# Security
list_db = True
dbfilter = 

# Performance
unaccent = False
EOF

chown $ODOO_USER:$ODOO_USER "$ODOO_CONFIG"

# Crear servicio systemd mejorado
log "🔧 Creando servicio systemd para Odoo..."
cat > /etc/systemd/system/odoo.service << EOF
[Unit]
Description=Odoo 18 Community Edition
Documentation=https://www.odoo.com
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/odoo-bin -c $ODOO_CONFIG
WorkingDirectory=$ODOO_HOME
StandardOutput=journal+console
StandardError=journal+console
Restart=always
RestartSec=10
KillMode=mixed
KillSignal=SIGINT

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/var/log/odoo /var/lib/odoo /tmp
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar Odoo
log "🚀 Iniciando servicio Odoo..."
systemctl daemon-reload
systemctl enable odoo

# Función mejorada para esperar que Odoo inicie
wait_for_odoo() {
    local max_attempts=60
    local attempt=1
    
    log "⏳ Esperando que Odoo inicie..."
    
    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active --quiet odoo; then
            # Verificar también que el puerto esté escuchando
            if netstat -tuln 2>/dev/null | grep -q ":$ODOO_PORT "; then
                log "✅ Odoo está ejecutándose y escuchando en puerto $ODOO_PORT"
                return 0
            fi
        fi
        
        if [ $((attempt % 10)) -eq 0 ]; then
            log "⏳ Esperando que Odoo inicie... (intento $attempt/$max_attempts)"
            # Mostrar últimas líneas del log para diagnóstico
            if [ -f /var/log/odoo/odoo.log ]; then
                info "Últimas líneas del log:"
                tail -5 /var/log/odoo/odoo.log
            fi
        fi
        
        sleep 2
        ((attempt++))
    done
    
    error "Odoo no pudo iniciarse después de $max_attempts intentos"
    systemctl status odoo --no-pager -l
    if [ -f /var/log/odoo/odoo.log ]; then
        error "Últimas líneas del log de Odoo:"
        tail -20 /var/log/odoo/odoo.log
    fi
    return 1
}

# Iniciar Odoo
systemctl start odoo

# Esperar que Odoo inicie
if ! wait_for_odoo; then
    error "No se pudo iniciar Odoo correctamente"
    exit 1
fi

# Inicializar base de datos si es necesario
log "🗄️ Verificando inicialización de base de datos..."
DB_EXISTS=$(sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -w "$POSTGRES_DB" | wc -l)

if [ "$DB_EXISTS" -eq 0 ]; then
    log "🗄️ Inicializando base de datos..."
    systemctl stop odoo
    
    if sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/python3" "$ODOO_HOME/odoo-bin" \
        -c "$ODOO_CONFIG" -d "$POSTGRES_DB" --init=base --stop-after-init; then
        log "✅ Base de datos inicializada correctamente"
    else
        error "Falló la inicialización de la base de datos"
        exit 1
    fi
    
    # Reiniciar Odoo después de la inicialización
    systemctl start odoo
    wait_for_odoo
else
    log "✅ Base de datos ya existe"
fi

# Obtener IP externa con mejor manejo
log "🌐 Obteniendo información de red..."
EXTERNAL_IP=$(curl -s --max-time 10 "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google" 2>/dev/null || echo "IP_NO_DISPONIBLE")

# Información final
log "🎉 ¡Instalación de Odoo completada exitosamente!"
echo "
╔══════════════════════════════════════════════════════════════════════════════╗
║                          🎉 ODOO 18 INSTALADO EXITOSAMENTE                  ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  📋 Información de la Instancia:                                           ║
║     • Instancia: $INSTANCE_NAME                                              ║
║     • Fecha de despliegue: $DEPLOYMENT_TIME                                  ║
║     • GitHub Actor: $GITHUB_ACTOR                                           ║
║                                                                              ║
║  🌐 Acceso Web:                                                             ║
║     • URL: http://$EXTERNAL_IP:$ODOO_PORT                                   ║
║     • Usuario administrador: admin                                           ║
║     • Contraseña: admin                                                      ║
║                                                                              ║
║  📁 Rutas importantes:                                                      ║
║     • Instalación: $ODOO_HOME                                              ║
║     • Configuración: $ODOO_CONFIG                                          ║
║     • Logs: /var/log/odoo/odoo.log                                          ║
║     • Datos: /var/lib/odoo                                                  ║
║                                                                              ║
║  🔧 Comandos útiles:                                                        ║
║     • Estado del servicio: systemctl status odoo                           ║
║     • Ver logs: tail -f /var/log/odoo/odoo.log                             ║
║     • Reiniciar: systemctl restart odoo                                     ║
╚══════════════════════════════════════════════════════════════════════════════╝
"

# Diagnóstico final mejorado
log "🔍 Diagnóstico final del sistema:"
echo "=== Estado del servicio Odoo ==="
systemctl status odoo --no-pager -l

echo -e "\n=== Estado de PostgreSQL ==="
systemctl status postgresql --no-pager -l

echo -e "\n=== Puertos en escucha ==="
netstat -tuln | grep -E ":($ODOO_PORT|5432) "

echo -e "\n=== Espacio en disco ==="
df -h /

echo -e "\n=== Memoria del sistema ==="
free -h

echo -e "\n=== Verificación de OpenSSL ==="
openssl version
sudo -u $ODOO_USER "$ODOO_HOME/venv/bin/python" -c "import OpenSSL; print('pyOpenSSL version:', OpenSSL.__version__)" 2>/dev/null || echo "Error verificando pyOpenSSL"

echo -e "\n=== Últimas líneas del log de Odoo ==="
if [ -f /var/log/odoo/odoo.log ]; then
    tail -15 /var/log/odoo/odoo.log
else
    echo "No hay log de Odoo disponible"
fi

log "✅ Script de instalación completado exitosamente"
