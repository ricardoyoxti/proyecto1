# 🚀 Deploy Odoo 18 to Google Cloud Platform

Deployment automatizado de Odoo 18 en Google Cloud Platform usando GitHub Actions.

## 🎯 Deploy Rápido

[![Deploy to GCP](https://img.shields.io/badge/Deploy%20to-Google%20Cloud-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)](../../actions/workflows/deploy-odoo-gcp.yml)

> **Clic en el botón de arriba para ir directamente al workflow de deployment**

## 📋 Descripción

Este repositorio contiene un workflow de GitHub Actions que permite desplegar automáticamente una instancia de Odoo 18 en Google Cloud Platform (GCP) con un solo clic.

## ✨ Características

- 🔧 Despliegue automatizado de Odoo 18
- ☁️ Configuración automática de VM en GCP
- 🔥 Reglas de firewall configuradas automáticamente
- 🎛️ Opciones personalizables de tipo de máquina y disco
- 📊 Información detallada del despliegue
- 🔒 Configuración segura usando GitHub Secrets

## 🛠️ Requisitos Previos

### 1. Cuenta de Google Cloud Platform
- Proyecto activo en GCP
- Facturación habilitada
- APIs habilitadas:
  - Compute Engine API
  - Cloud Resource Manager API

### 2. Service Account de GCP
Crear una service account con los siguientes roles:
- `Compute Admin`
- `Service Account User` 
- `Security Admin`

### 3. GitHub Secrets
Configurar los siguientes secrets en el repositorio:

| Secret Name | Descripción | Ejemplo |
|------------|-------------|---------|
| `GCP_PROJECT_ID` | ID del proyecto de GCP | `mi-proyecto-123456` |
| `GCP_SA_KEY` | Clave JSON de la service account | `{...}` (JSON completo) |
| `GCP_SERVICE_ACCOUNT_EMAIL` | Email de la service account | `mi-sa@proyecto.iam.gserviceaccount.com` |

## 🚀 Cómo usar

### 1. Configurar Secrets
1. Ve a tu repositorio en GitHub
2. `Settings` → `Secrets and variables` → `Actions`
3. Agrega los 3 secrets mencionados arriba

### 2. Ejecutar el Workflow
1. Ve a la pestaña `Actions` en tu repositorio
2. Selecciona el workflow "🚀 Deploy Odoo 18 to Google Cloud"
3. Clic en `Run workflow`
4. Configura los parámetros:
   - **Nombre de instancia**: Base del nombre (se añade timestamp único)
   - **Tipo de máquina**: e2-micro, e2-small, e2-medium, e2-standard-2, e2-standard-4
   - **Zona**: us-central1-a (por defecto)
   - **Tamaño del disco**: 20GB (por defecto)

### 3. Acceder a Odoo
Una vez completado el despliegue:
- La instalación tarda 5-10 minutos adicionales
- Accede via: `http://IP_EXTERNA:8069`
- Credenciales por defecto:
  - **Database**: odoo
  - **Usuario**: admin
  - **Contraseña**: admin

## 📁 Estructura del Proyecto

```
.
├── .github/
│   └── workflows/
│       └── deploy-odoo-gcp.yml    # Workflow principal
├── startup-script.sh              # Script de instalación de Odoo
├── README.md                      # Este archivo
└── ...
```

## ⚙️ Configuración de Parámetros

### Tipos de Máquina Disponibles
- `e2-micro`: 1 vCPU, 1GB RAM (ideal para pruebas)
- `e2-small`: 1 vCPU, 2GB RAM
- `e2-medium`: 1 vCPU, 4GB RAM
- `e2-standard-2`: 2 vCPUs, 8GB RAM (recomendado)
- `e2-standard-4`: 4 vCPUs, 16GB RAM (producción)

### Zonas Disponibles
- `us-central1-a` (por defecto)
- `us-east1-b`
- `europe-west1-b`
- `asia-east1-a`

## 🔧 Personalización

### Modificar el Script de Instalación
Puedes personalizar la instalación editando `startup-script.sh`:
- Agregar módulos adicionales
- Configurar base de datos personalizada
- Instalar dependencias extra

### Ajustar Configuración de VM
Modifica el workflow `deploy-odoo-gcp.yml` para:
- Cambiar configuración de red
- Agregar discos adicionales
- Modificar etiquetas y metadatos

## 🗑️ Limpieza

Para eliminar la instancia creada:

```bash
gcloud compute instances delete NOMBRE_INSTANCIA --zone=ZONA
```

O desde la consola de GCP:
1. Ve a Compute Engine → VM instances  
2. Selecciona la instancia
3. Clic en "Delete"

## 🔒 Seguridad

- ✅ Credenciales almacenadas como GitHub Secrets
- ✅ Service Account con permisos mínimos necesarios
- ✅ Firewall configurado solo para puertos necesarios
- ⚠️ **Importante**: Cambia las credenciales por defecto de Odoo después del primer acceso

## 📝 Logs y Troubleshooting

### Ver logs de instalación:
```bash
gcloud compute ssh NOMBRE_INSTANCIA --zone=ZONA
sudo journalctl -u google-startup-scripts.service
```

### Verificar estado de Odoo:
```bash
sudo systemctl status odoo
sudo tail -f /var/log/odoo/odoo.log
```

## 🤝 Contribuir

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📜 Licencia

Este proyecto está bajo la Licencia MIT - ver el archivo [LICENSE](LICENSE) para detalles.

## 🆘 Soporte

Si tienes problemas o preguntas:
1. Revisa los [Issues](../../issues) existentes
2. Crea un nuevo issue con detalles del problema
3. Incluye logs relevantes y configuración usada

## 📚 Recursos Adicionales

- [Documentación oficial de Odoo](https://www.odoo.com/documentation)
- [Google Cloud Documentation](https://cloud.google.com/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

**⚡ Hecho con ❤️ para simplificar el despliegue de Odoo**
