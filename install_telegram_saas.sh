#!/bin/bash

# =============================================================================
# SCRIPT DE INSTALAÇÃO AUTOMATIZADA - TELEGRAM SAAS MULTI-CONTA
# =============================================================================
# Autor: Desenvolvido para replicação rápida em VPS Ubuntu 22.04
# Versão: 1.0
# Data: 27/06/2025
# =============================================================================

set -e  # Parar execução em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log colorido
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função para verificar se comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Função para verificar se é Ubuntu 22.04
check_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "22.04" ]]; then
            return 0
        fi
    fi
    return 1
}

# Banner de início
echo -e "${BLUE}"
echo "============================================================================="
echo "    INSTALADOR AUTOMÁTICO - TELEGRAM SAAS MULTI-CONTA"
echo "============================================================================="
echo -e "${NC}"

# Verificar se é root ou tem sudo
if [[ $EUID -ne 0 ]] && ! command_exists sudo; then
    log_error "Este script precisa ser executado como root ou com sudo disponível"
    exit 1
fi

# Verificar versão do Ubuntu
if ! check_ubuntu_version; then
    log_warning "Este script foi testado apenas no Ubuntu 22.04"
    read -p "Deseja continuar mesmo assim? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Instalação cancelada pelo usuário"
        exit 0
    fi
fi

# Definir diretório de instalação
INSTALL_DIR="/root/telegram-saas"
GITHUB_URL="https://github.com/Lucasfig199/TEL-SAAS/raw/main/telegram-saas.v2.zip"

log_info "Iniciando instalação da plataforma Telegram SaaS..."

# 1. Atualizar sistema e instalar dependências
log_info "Atualizando sistema e instalando dependências..."
if command_exists sudo; then
    sudo apt update && sudo apt upgrade -y
    sudo apt install python3 python3-pip python3-venv wget unzip -y
else
    apt update && apt upgrade -y
    apt install python3 python3-pip python3-venv wget unzip -y
fi

log_success "Sistema atualizado e dependências instaladas"

# 2. Criar diretório e baixar projeto
log_info "Baixando projeto do GitHub..."
cd /tmp
wget -O telegram-saas.v2.zip "$GITHUB_URL"

if [[ ! -f telegram-saas.v2.zip ]]; then
    log_error "Falha ao baixar o projeto do GitHub"
    exit 1
fi

log_success "Projeto baixado com sucesso"

# 3. Extrair e mover para diretório final
log_info "Extraindo e configurando projeto..."
unzip -o telegram-saas.v2.zip

# Remover diretório existente se houver
if [[ -d "$INSTALL_DIR" ]]; then
    log_warning "Diretório $INSTALL_DIR já existe. Removendo..."
    rm -rf "$INSTALL_DIR"
fi

# Mover projeto para diretório final
mv telegram-saas.v2 "$INSTALL_DIR"
cd "$INSTALL_DIR"

log_success "Projeto extraído e movido para $INSTALL_DIR"

# 4. Configurar permissões do ambiente virtual
log_info "Configurando permissões do ambiente virtual..."
chmod +x venv/bin/*

# 5. Limpar arquivos de configuração para nova instalação
log_info "Limpando configurações para nova instalação..."
rm -f accounts.json
rm -f session_*.session

# Criar arquivo config.json padrão (sem webhook configurado)
cat > config.json << 'EOF'
{
  "webhook_url": ""
}
EOF

log_success "Configurações limpas para nova instalação"

# 6. Criar arquivos de serviço systemd
log_info "Configurando serviços systemd..."

# Serviço da API
cat > /etc/systemd/system/telegram-api.service << EOF
[Unit]
Description=Telegram API Server
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/python telegram_api_v3.py
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=telegram-api

[Install]
WantedBy=multi-user.target
EOF

log_success "Serviços systemd configurados"

# 7. Recarregar systemd e habilitar serviços
log_info "Habilitando e iniciando serviços..."
systemctl daemon-reload
systemctl enable telegram-api

# 8. Iniciar serviço
systemctl start telegram-api

# Aguardar alguns segundos para o serviço inicializar
sleep 5

# 9. Verificar status do serviço
if systemctl is-active --quiet telegram-api; then
    log_success "Serviço telegram-api iniciado com sucesso"
else
    log_error "Falha ao iniciar o serviço telegram-api"
    log_info "Verificando logs do serviço..."
    systemctl status telegram-api --no-pager -l
    exit 1
fi

# 10. Obter IP da VPS
VPS_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')

# 11. Criar script de gerenciamento
log_info "Criando script de gerenciamento..."
cat > /usr/local/bin/telegram-saas << 'EOF'
#!/bin/bash

case "$1" in
    start)
        systemctl start telegram-api
        echo "Serviço iniciado"
        ;;
    stop)
        systemctl stop telegram-api
        echo "Serviço parado"
        ;;
    restart)
        systemctl restart telegram-api
        echo "Serviço reiniciado"
        ;;
    status)
        systemctl status telegram-api --no-pager
        ;;
    logs)
        journalctl -u telegram-api -f
        ;;
    dashboard)
        VPS_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
        echo "Dashboard disponível em: http://$VPS_IP:5000"
        ;;
    *)
        echo "Uso: telegram-saas {start|stop|restart|status|logs|dashboard}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/telegram-saas

log_success "Script de gerenciamento criado em /usr/local/bin/telegram-saas"

# 12. Limpeza
log_info "Limpando arquivos temporários..."
rm -f /tmp/telegram-saas.v2.zip
rm -rf /tmp/telegram-saas.v2

# 13. Exibir informações finais
echo
echo -e "${GREEN}============================================================================="
echo "    INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "=============================================================================${NC}"
echo
echo -e "${BLUE}📋 INFORMAÇÕES DA INSTALAÇÃO:${NC}"
echo "   • Diretório: $INSTALL_DIR"
echo "   • Serviço: telegram-api.service"
echo "   • Dashboard: http://$VPS_IP:5000"
echo
echo -e "${BLUE}🚀 COMANDOS ÚTEIS:${NC}"
echo "   • telegram-saas start      - Iniciar serviço"
echo "   • telegram-saas stop       - Parar serviço"
echo "   • telegram-saas restart    - Reiniciar serviço"
echo "   • telegram-saas status     - Ver status"
echo "   • telegram-saas logs       - Ver logs em tempo real"
echo "   • telegram-saas dashboard  - Mostrar URL do dashboard"
echo
echo -e "${BLUE}📱 PRÓXIMOS PASSOS:${NC}"
echo "   1. Acesse o dashboard: http://$VPS_IP:5000"
echo "   2. Vá para a aba 'Contas'"
echo "   3. Conecte suas contas Telegram"
echo "   4. Configure o webhook se necessário"
echo
echo -e "${YELLOW}⚠️  IMPORTANTE:${NC}"
echo "   • Certifique-se de que a porta 5000 está aberta no firewall"
echo "   • Use 'telegram-saas logs' para monitorar problemas"
echo "   • O arquivo de configuração está em: $INSTALL_DIR/config.json"
echo
echo -e "${GREEN}✅ Instalação finalizada! Sua plataforma Telegram SaaS está pronta para uso.${NC}"
echo

