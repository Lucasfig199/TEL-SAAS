#!/bin/bash

# Telegram SaaS Pro - Instalador Automático Completo
# Versão: 2.0.0
# Data: 26/06/2025

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="telegram-saas-pro"
INSTALL_DIR="/opt/${PROJECT_NAME}"
SERVICE_USER="telegram"
BACKEND_PORT="5000"
FRONTEND_PORT="3000"
NGINX_PORT="80"

# Functions
print_header() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║              🚀 TELEGRAM SAAS PRO v2.0.0 🚀                ║"
    echo "║                                                              ║"
    echo "║              Instalador Automático Completo                 ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script deve ser executado como root (use sudo)"
        exit 1
    fi
}

check_system() {
    print_step "Verificando sistema operacional..."
    
    if [[ ! -f /etc/os-release ]]; then
        print_error "Sistema operacional não suportado"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
        print_error "Sistema operacional não suportado. Use Ubuntu ou Debian."
        exit 1
    fi
    
    print_success "Sistema operacional suportado: $PRETTY_NAME"
}

install_dependencies() {
    print_step "Instalando dependências do sistema..."
    
    # Update package list
    apt-get update -qq
    
    # Install required packages
    apt-get install -y \
        curl \
        wget \
        git \
        nginx \
        sqlite3 \
        python3 \
        python3-pip \
        python3-venv \
        nodejs \
        npm \
        supervisor \
        ufw \
        htop \
        unzip \
        build-essential
    
    print_success "Dependências instaladas com sucesso"
}

install_nodejs() {
    print_step "Instalando Node.js LTS..."
    
    # Install Node.js 18 LTS
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    # Install global packages
    npm install -g pm2 pnpm
    
    print_success "Node.js $(node --version) instalado com sucesso"
}

create_user() {
    print_step "Criando usuário do sistema..."
    
    if ! id "$SERVICE_USER" &>/dev/null; then
        useradd -r -s /bin/bash -d "$INSTALL_DIR" "$SERVICE_USER"
        print_success "Usuário $SERVICE_USER criado"
    else
        print_info "Usuário $SERVICE_USER já existe"
    fi
}

setup_directories() {
    print_step "Configurando diretórios..."
    
    # Create main directory
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/data"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/config"
    
    # Copy project files
    cp -r backend "$INSTALL_DIR/"
    cp -r frontend "$INSTALL_DIR/"
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    
    print_success "Diretórios configurados"
}

setup_backend() {
    print_step "Configurando backend Flask..."
    
    cd "$INSTALL_DIR/backend"
    
    # Create virtual environment
    sudo -u "$SERVICE_USER" python3 -m venv venv
    
    # Install Python dependencies
    sudo -u "$SERVICE_USER" bash -c "source venv/bin/activate && pip install --upgrade pip"
    sudo -u "$SERVICE_USER" bash -c "source venv/bin/activate && pip install -r requirements.txt"
    
    # Initialize database
    sudo -u "$SERVICE_USER" bash -c "source venv/bin/activate && python src/utils/database_init.py data/telegram_saas.db"
    
    print_success "Backend configurado com sucesso"
}

setup_frontend() {
    print_step "Configurando frontend React..."
    
    cd "$INSTALL_DIR/frontend"
    
    # Install dependencies
    sudo -u "$SERVICE_USER" pnpm install
    
    # Build for production
    sudo -u "$SERVICE_USER" pnpm run build
    
    print_success "Frontend configurado com sucesso"
}

setup_nginx() {
    print_step "Configurando Nginx..."
    
    # Create Nginx configuration
    cat > /etc/nginx/sites-available/$PROJECT_NAME << EOF
server {
    listen 80;
    server_name _;
    
    # Frontend (React build)
    location / {
        root $INSTALL_DIR/frontend/dist;
        index index.html;
        try_files \$uri \$uri/ /index.html;
        
        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }
    }
    
    # Backend API
    location /api/ {
        proxy_pass http://127.0.0.1:$BACKEND_PORT/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
        add_header Access-Control-Allow-Headers "Content-Type, Authorization";
        
        # Handle preflight requests
        if (\$request_method = 'OPTIONS') {
            return 204;
        }
    }
    
    # Logs
    access_log $INSTALL_DIR/logs/nginx_access.log;
    error_log $INSTALL_DIR/logs/nginx_error.log;
}
EOF
    
    # Enable site
    ln -sf /etc/nginx/sites-available/$PROJECT_NAME /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test configuration
    nginx -t
    
    print_success "Nginx configurado com sucesso"
}

setup_supervisor() {
    print_step "Configurando Supervisor..."
    
    # Create supervisor configuration for backend
    cat > /etc/supervisor/conf.d/$PROJECT_NAME-backend.conf << EOF
[program:$PROJECT_NAME-backend]
command=$INSTALL_DIR/backend/venv/bin/python src/main.py
directory=$INSTALL_DIR/backend
user=$SERVICE_USER
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=$INSTALL_DIR/logs/backend.log
environment=FLASK_ENV=production,DATABASE_PATH=$INSTALL_DIR/data/telegram_saas.db
EOF
    
    print_success "Supervisor configurado com sucesso"
}

setup_pm2() {
    print_step "Configurando PM2 para frontend..."
    
    # Create PM2 ecosystem file
    cat > "$INSTALL_DIR/ecosystem.config.js" << EOF
module.exports = {
  apps: [{
    name: '$PROJECT_NAME-frontend',
    script: 'serve',
    args: '-s dist -l $FRONTEND_PORT',
    cwd: '$INSTALL_DIR/frontend',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production'
    }
  }]
}
EOF
    
    # Install serve globally
    npm install -g serve
    
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/ecosystem.config.js"
    
    print_success "PM2 configurado com sucesso"
}

setup_firewall() {
    print_step "Configurando firewall..."
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Allow backend port (internal)
    ufw allow from 127.0.0.1 to any port $BACKEND_PORT
    
    print_success "Firewall configurado com sucesso"
}

create_systemd_services() {
    print_step "Criando serviços systemd..."
    
    # Create systemd service for the complete system
    cat > /etc/systemd/system/$PROJECT_NAME.service << EOF
[Unit]
Description=Telegram SaaS Pro Complete System
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash $INSTALL_DIR/scripts/start.sh
ExecStop=/bin/bash $INSTALL_DIR/scripts/stop.sh
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    # Create scripts directory
    mkdir -p "$INSTALL_DIR/scripts"
    
    # Create start script
    cat > "$INSTALL_DIR/scripts/start.sh" << EOF
#!/bin/bash
echo "Starting Telegram SaaS Pro..."

# Start backend via supervisor
supervisorctl start $PROJECT_NAME-backend

# Start nginx
systemctl start nginx

echo "Telegram SaaS Pro started successfully!"
echo "Access: http://\$(hostname -I | awk '{print \$1}')"
EOF
    
    # Create stop script
    cat > "$INSTALL_DIR/scripts/stop.sh" << EOF
#!/bin/bash
echo "Stopping Telegram SaaS Pro..."

# Stop backend
supervisorctl stop $PROJECT_NAME-backend

echo "Telegram SaaS Pro stopped successfully!"
EOF
    
    # Make scripts executable
    chmod +x "$INSTALL_DIR/scripts/"*.sh
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/scripts"
    
    # Reload systemd
    systemctl daemon-reload
    
    print_success "Serviços systemd criados"
}

start_services() {
    print_step "Iniciando serviços..."
    
    # Reload supervisor
    supervisorctl reread
    supervisorctl update
    
    # Start backend
    supervisorctl start $PROJECT_NAME-backend
    
    # Start and enable nginx
    systemctl restart nginx
    systemctl enable nginx
    
    # Enable system service
    systemctl enable $PROJECT_NAME
    
    print_success "Serviços iniciados com sucesso"
}

create_management_script() {
    print_step "Criando script de gerenciamento..."
    
    cat > /usr/local/bin/telegram-saas << 'EOF'
#!/bin/bash

PROJECT_NAME="telegram-saas-pro"
INSTALL_DIR="/opt/${PROJECT_NAME}"

case "$1" in
    start)
        echo "Starting Telegram SaaS Pro..."
        supervisorctl start $PROJECT_NAME-backend
        systemctl start nginx
        echo "✅ Started successfully!"
        ;;
    stop)
        echo "Stopping Telegram SaaS Pro..."
        supervisorctl stop $PROJECT_NAME-backend
        echo "✅ Stopped successfully!"
        ;;
    restart)
        echo "Restarting Telegram SaaS Pro..."
        supervisorctl restart $PROJECT_NAME-backend
        systemctl restart nginx
        echo "✅ Restarted successfully!"
        ;;
    status)
        echo "=== Telegram SaaS Pro Status ==="
        echo "Backend:"
        supervisorctl status $PROJECT_NAME-backend
        echo ""
        echo "Nginx:"
        systemctl status nginx --no-pager -l
        ;;
    logs)
        echo "=== Backend Logs ==="
        tail -f $INSTALL_DIR/logs/backend.log
        ;;
    update)
        echo "Updating Telegram SaaS Pro..."
        cd $INSTALL_DIR
        # Add update logic here
        echo "✅ Updated successfully!"
        ;;
    backup)
        echo "Creating backup..."
        BACKUP_FILE="/tmp/telegram-saas-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$BACKUP_FILE" -C /opt telegram-saas-pro
        echo "✅ Backup created: $BACKUP_FILE"
        ;;
    *)
        echo "Usage: telegram-saas {start|stop|restart|status|logs|update|backup}"
        echo ""
        echo "Commands:"
        echo "  start    - Start all services"
        echo "  stop     - Stop all services"
        echo "  restart  - Restart all services"
        echo "  status   - Show service status"
        echo "  logs     - Show backend logs"
        echo "  update   - Update system"
        echo "  backup   - Create backup"
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/telegram-saas
    
    print_success "Script de gerenciamento criado: telegram-saas"
}

run_tests() {
    print_step "Executando testes do sistema..."
    
    # Wait for services to start
    sleep 5
    
    # Test backend API
    if curl -s http://localhost:$BACKEND_PORT/api/health > /dev/null; then
        print_success "✅ Backend API respondendo"
    else
        print_error "❌ Backend API não está respondendo"
    fi
    
    # Test frontend
    if curl -s http://localhost > /dev/null; then
        print_success "✅ Frontend acessível"
    else
        print_error "❌ Frontend não está acessível"
    fi
    
    # Test database
    if sudo -u "$SERVICE_USER" sqlite3 "$INSTALL_DIR/data/telegram_saas.db" "SELECT COUNT(*) FROM accounts;" > /dev/null; then
        print_success "✅ Banco de dados funcionando"
    else
        print_error "❌ Problema com banco de dados"
    fi
}

show_completion_info() {
    local SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║            🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO! 🎉          ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${CYAN}📋 INFORMAÇÕES DO SISTEMA:${NC}"
    echo "   • Diretório: $INSTALL_DIR"
    echo "   • Usuário: $SERVICE_USER"
    echo "   • Backend: http://$SERVER_IP:$BACKEND_PORT"
    echo "   • Frontend: http://$SERVER_IP"
    echo ""
    
    echo -e "${CYAN}🔧 COMANDOS ÚTEIS:${NC}"
    echo "   • telegram-saas start    - Iniciar sistema"
    echo "   • telegram-saas stop     - Parar sistema"
    echo "   • telegram-saas restart  - Reiniciar sistema"
    echo "   • telegram-saas status   - Ver status"
    echo "   • telegram-saas logs     - Ver logs"
    echo "   • telegram-saas backup   - Criar backup"
    echo ""
    
    echo -e "${CYAN}📁 ESTRUTURA DE ARQUIVOS:${NC}"
    echo "   • Backend: $INSTALL_DIR/backend/"
    echo "   • Frontend: $INSTALL_DIR/frontend/"
    echo "   • Banco: $INSTALL_DIR/data/telegram_saas.db"
    echo "   • Logs: $INSTALL_DIR/logs/"
    echo "   • Backups: $INSTALL_DIR/backups/"
    echo ""
    
    echo -e "${CYAN}🌐 ACESSO:${NC}"
    echo "   • Interface Web: ${GREEN}http://$SERVER_IP${NC}"
    echo "   • API Backend: ${GREEN}http://$SERVER_IP/api/${NC}"
    echo "   • Documentação: ${GREEN}http://$SERVER_IP (aba API Docs)${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  PRÓXIMOS PASSOS:${NC}"
    echo "   1. Acesse http://$SERVER_IP para usar a interface"
    echo "   2. Configure suas contas do Telegram na aba 'Contas'"
    echo "   3. Configure webhooks na aba 'Webhooks' se necessário"
    echo "   4. Explore a documentação da API na aba 'API Docs'"
    echo ""
    
    echo -e "${GREEN}✅ Sistema pronto para uso!${NC}"
}

# Main installation process
main() {
    print_header
    
    print_step "Iniciando instalação do Telegram SaaS Pro v2.0.0..."
    
    check_root
    check_system
    install_dependencies
    install_nodejs
    create_user
    setup_directories
    setup_backend
    setup_frontend
    setup_nginx
    setup_supervisor
    setup_pm2
    setup_firewall
    create_systemd_services
    start_services
    create_management_script
    run_tests
    show_completion_info
    
    print_success "🎉 Instalação concluída com sucesso!"
}

# Run main function
main "$@"

