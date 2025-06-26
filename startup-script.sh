#!/bin/bash
# startup-script.sh - Script de instalación automática de Odoo 18 Community y PostgreSQL

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función de logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Obtener información de metadata de GCP
INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/instance-name" -H "Metadata-Flavor: Google" || echo "odoo-instance")
DEPLOYMENT_TIME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/deployment-time" -H "Metadata-Flavor: Google" || date -u +"%Y-%m-%dT%H:%M:%SZ")
GITHUB_ACTOR=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/attributes/github-actor" -H "Metadata-Flavor: Google" || echo "unknown")

# Variables de configuración
ODOO_VERSION="18.0"
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_CONFIG="/etc/odoo/odoo.conf"
POSTGRES_USER="odoo"
POSTGRES_DB="odoo"
POSTGRES_PASSWORD="odoo123"

log "🚀 Iniciando instalación de Odoo 18 Community en Google Cloud Platform"
info "📋 Información del despliegue:"
info "   - Instancia: $INSTANCE_NAME"
info "   - Desplegado por: $GITHUB_ACTOR"
info "   - Fecha: $DEPLOYMENT_TIME"

# Actualizar sistema
log "📦 Actualizando paquetes del sistema..."
apt-get update -y
apt-get upgrade -y

# Instalar dependencias del sistema
log "🔧 Instalando dependencias del sistema..."
apt-get install -y \
    wget \
    git \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    python3-wheel \
    libxml2-dev \
    libxslt1-dev \
    libevent-dev \
    libsasl2-dev \
    libldap2-dev \
    libpq-dev \
    libjpeg-dev \
    libpng-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libwebp-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libxcb1-dev \
    pkg-config \
    gcc \
    g++ \
    make \
    curl \
    unzip \
    fontconfig \
    libfontconfig1 \
    wkhtmltopdf \
    xfonts-75dpi \
    xfonts-base

# Instalar PostgreSQL
log "🐘 Instalando PostgreSQL..."
apt-get install -y postgresql postgresql-contrib postgresql-server-dev-all

# Configurar PostgreSQL
log "🔐 Configurando PostgreSQL..."
systemctl start postgresql
systemctl enable postgresql

# Crear usuario y base de datos para Odoo
sudo -u postgres psql -c "CREATE USER $POSTGRES_USER WITH CREATEDB PASSWORD '$POSTGRES_PASSWORD';"
sudo -u postgres psql -c "ALTER USER $POSTGRES_USER CREATEDB;"

# Crear usuario del sistema para Odoo
log "👤 Creando usuario del sistema para Odoo..."
adduser --system --home=$ODOO_HOME --group $ODOO_USER

# Instalar wkhtmltopdf (versión específica recomendada)
log "📄 Instalando wkhtmltopdf..."
cd /tmp
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb || apt-get install -f -y
dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb

# Descargar Odoo 18
log "📥 Descargando Odoo 18 Community..."
cd /opt
git clone https://www.github.com/odoo/odoo --depth 1 --branch $ODOO_VERSION --single-branch odoo
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

# Crear directorio de configuración
mkdir -p /etc/odoo
mkdir -p /var/log/odoo
chown $ODOO_USER:$ODOO_USER /var/log/odoo

# Instalar dependencias Python de Odoo
log "🐍 Instalando dependencias Python..."
cd $ODOO_HOME
sudo -u $ODOO_USER python3 -m pip install --upgrade pip
sudo -u $ODOO_USER python3 -m pip install -r requirements.txt
sudo -u $ODOO_USER python3 -m pip install psycopg2-binary

# Crear archivo de configuración de Odoo
log "⚙️ Creando archivo de configuración..."
cat > $ODOO_CONFIG << EOF
[options]
; Configuración básica de Odoo 18
admin_passwd = admin
db_host = localhost
db_port = 5432
db_user = $POSTGRES_USER
db_password = $POSTGRES_PASSWORD
addons_path = $ODOO_HOME/addons
logfile = /var/log/odoo/odoo.log
log_level = info
xmlrpc_port = 8069
longpolling_port = 8072

; Configuración de límites
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
limit_time_real_cron = -1
max_cron_threads = 1
workers = 0

; Configuración de seguridad
list_db = True
proxy_mode = False

; Configuración de archivos
data_dir = /var/lib/odoo
EOF

chown $ODOO_USER:$ODOO_USER $ODOO_CONFIG

# Crear directorio de datos
mkdir -p /var/lib/odoo
chown $ODOO_USER:$ODOO_USER /var/lib/odoo

# Crear servicio systemd
log "🔧 Creando servicio systemd..."
cat > /etc/systemd/system/odoo.service << EOF
[Unit]
Description=Odoo 18 Community
Documentation=http://www.odoo.com
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/odoo-bin -c $ODOO_CONFIG
StandardOutput=journal+console
KillMode=mixed
KillSignal=SIGINT
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar el servicio
log "🚀 Habilitando e iniciando servicio Odoo..."
systemctl daemon-reload
systemctl enable odoo
systemctl start odoo

# Configurar firewall UFW (si está instalado)
if command -v ufw &> /dev/null; then
    log "🔥 Configurando firewall UFW..."
    ufw allow 8069/tcp
    ufw allow 22/tcp
    ufw --force enable
fi

# Esperar a que Odoo inicie completamente
log "⏳ Esperando a que Odoo inicie completamente..."
sleep 30

# Verificar estado del servicio
log "✅ Verificando estado del servicio..."
systemctl status odoo --no-pager -l

# Crear base de datos inicial
log "🗄️ Creando base de datos inicial..."
sleep 10
sudo -u $ODOO_USER $ODOO_HOME/odoo-bin -c $ODOO_CONFIG -d odoo --init=base --stop-after-init

# Información final
log "🎉 ¡Instalación completada exitosamente!"
log "📊 Información de la instalación:"
echo ""
info "🌐 Odoo estará disponible en: http://$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H 'Metadata-Flavor: Google'):8069"
info "🗄️ Base de datos: odoo"
info "👤 Usuario administrador: admin"
info "🔐 Contraseña: admin"
info "📁 Directorio de Odoo: $ODOO_HOME"
info "⚙️ Archivo de configuración: $ODOO_CONFIG"
info "📋 Logs: /var/log/odoo/odoo.log"
info "🔧 Gestión del servicio:"
info "   - Iniciar: sudo systemctl start odoo"
info "   - Detener: sudo systemctl stop odoo"
info "   - Reiniciar: sudo systemctl restart odoo"
info "   - Estado: sudo systemctl status odoo"

# Crear script de información
cat > /home/ubuntu/odoo-info.sh << EOF
#!/bin/bash
echo "🔍 INFORMACIÓN DE ODOO 18"
echo "========================"
echo "🏷️ Instancia: $INSTANCE_NAME"
echo "👤 Desplegado por: $GITHUB_ACTOR"
echo "📅 Fecha de despliegue: $DEPLOYMENT_TIME"
echo "🌐 URL: http://\$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H 'Metadata-Flavor: Google'):8069"
echo "👤 Usuario: admin"
echo "🔐 Contraseña: admin"
echo ""
echo "🔧 COMANDOS ÚTILES:"
echo "sudo systemctl status odoo    # Ver estado"
echo "sudo systemctl restart odoo   # Reiniciar"
echo "sudo tail -f /var/log/odoo/odoo.log  # Ver logs"
echo ""
echo "🗑️ ELIMINAR INSTANCIA:"
echo "gcloud compute instances delete $INSTANCE_NAME --zone=\$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/zone -H 'Metadata-Flavor: Google' | cut -d/ -f4)"
EOF

chmod +x /home/ubuntu/odoo-info.sh
chown ubuntu:ubuntu /home/ubuntu/odoo-info.sh

log "✨ ¡Todo listo! Puedes acceder a Odoo en unos minutos."
log "💡 Tip: Ejecuta ./odoo-info.sh para ver la información de acceso"
