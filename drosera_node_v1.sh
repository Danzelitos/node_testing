#!/bin/bash

# Цвета текста
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

function show_logo() {
    echo -e "${CLR_SUCCESS}**********************************************************${CLR_RESET}"
    echo -e "${CLR_INFO}          Установочный скрипт для Drosera             ${CLR_RESET}"
    echo -e "${CLR_SUCCESS}**********************************************************${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

function install_dependencies() {
    echo -e "${CLR_WARNING}🔄 Проверяем и устанавливаем необходимые зависимости...${CLR_RESET}"
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt install curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev  -y

    sudo apt update -y && sudo apt upgrade -y
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg; done

  sudo apt-get update
  sudo apt-get install ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  
  echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  sudo apt update -y && sudo apt upgrade -y
  
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  
  # Test Docker
  sudo systemctl start docker
  sleep 3
  sudo docker run hello-world
}

function install_trap() {
  install_dependencies
  sleep 5
  curl -L https://app.drosera.io/install | bash
  sleep 3
  source /root/.bashrc
  droseraup

  sleep 5

  curl -L https://foundry.paradigm.xyz | bash
  sleep 3
  source /root/.bashrc
  foundryup

  sleep 5

  curl -fsSL https://bun.sh/install | bash
}

function deploy_trap() {
  mkdir my-drosera-trap
  cd my-drosera-trap

  echo -e "${YELLOW}Введите вашу Github почту:${NC} "
  read GITHUB_EMAIL
  # Запрос Username
  echo -e "${YELLOW}Введите ваш Github юзернейм:${NC} "
  read GITHUB_USERNAME
        
  # Применяем настройки git
  git config --global user.email "$GITHUB_EMAIL"
  git config --global user.name "$GITHUB_USERNAME"

  forge init -t drosera-network/trap-foundry-template

  curl -fsSL https://bun.sh/install | bash
  bun install
  sleep 3
  source $HOME/.bashrc
  forge build

  echo -e "${YELLOW}Введите ваш приватный ключ от EVM кошелька:${NC} "
  read PRIV_KEY

  DROSERA_PRIVATE_KEY="$PRIV_KEY" drosera apply

  echo -e "${YELLOW}Выполните дальнейшие действия по гайду${NC} "

  # drosera dryrun
}

function create_operator () {
  read -p "Введите ваш адрес кошелька: " WALLET && sed -i "/^private_trap/c\private_trap = true" my-drosera-trap/drosera.toml && sed -i "/^whitelist/c\whitelist = [\"$WALLET\"]" my-drosera-trap/drosera.toml
  echo -e "${YELLOW}Введите ваш приватный ключ от EVM кошелька:${NC} "
  read PRIV_KEY

  DROSERA_PRIVATE_KEY="$PRIV_KEY" drosera apply
}

function install_cli () {
  cd ~ 
  curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
  tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz

  ./drosera-operator --version

  sleep 5

  sudo cp drosera-operator /usr/bin
  sleep 3
  drosera-operator

  docker pull ghcr.io/drosera-network/drosera-operator:latest

  echo -e "${YELLOW}Введите ваш приватный ключ от EVM кошелька:${NC} "
  read PRIV_KEY
  drosera-operator register --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key "$PRIV_KEY"

  echo -e "${YELLOW}Введите ваш IP сервера:${NC} "
  read IP_ADDRESS

sudo bash -c "cat <<EOF > /etc/systemd/system/drosera.service
[Unit]
Description=drosera node service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=$(which drosera-operator) node --db-file-path \$HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \\
    --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com \\
    --eth-backup-rpc-url https://1rpc.io/holesky \\
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \\
    --eth-private-key $PRIV_KEY \\
    --listen-address 0.0.0.0 \\
    --network-external-p2p-address $IP_ADDRESS \\
    --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF"

  # Enable firewall
  sudo ufw allow ssh
  sudo ufw allow 22
  sudo ufw enable
  
  # Allow Drosera ports
  sudo ufw allow 31313/tcp
  sudo ufw allow 31314/tcp
  sleep 3
  
  sudo systemctl daemon-reload
  sudo systemctl enable drosera
  sudo systemctl start drosera

}

function check_logs () {
  echo -e "${YELLOW}Логи ноды Drosera: ${NC} "
  journalctl -u drosera.service -f
}

function restart_node () {
  echo -e "${YELLOW}Перезапуск ноды: ${NC} "
  sudo systemctl restart drosera
}

function delete_node () {
  read -p "⚠ Удалить ноду Drosera? (y/n): " CONFIRM
  if [[ "$CONFIRM" == "y" ]]; then
    echo -e "${YELLOW}Удаляю ноду Drosera...${NC} "
    sudo systemctl stop drosera.service
    sudo systemctl disable drosera.service
    sudo rm /etc/systemd/system/drosera.service
    rm -rf $HOME/.drosera $HOME/.bun $HOME/.drosera.db $HOME/.foundry $HOME/my-drosera-trap $HOME/drosera-operator $HOME/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    echo -e "${CLR_SUCCESS}✅ Нода полностью удалена.${CLR_RESET}"
  else
      echo -e "${CLR_INFO}▶ Отмена удаления.${CLR_RESET}"
  fi
}

# Главное меню
function show_menu() {
    show_logo
    echo -e "${CLR_GREEN}1) ⚙️  Подготовка Trap${CLR_RESET}"
    echo -e "${CLR_GREEN}2) ⛓️  Установить Trap${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 🖥️  Создать оператора ноды${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 🚀 Запуск ноды${CLR_RESET}"
    echo -e "${CLR_GREEN}2) 🔄 Перезапустить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}3) 📜 Просмотр логов${CLR_RESET}"
    echo -e "${CLR_GREEN}4) 🗑️  Удалить ноду${CLR_RESET}"
    echo -e "${CLR_GREEN}5) ❌ Выйти${CLR_RESET}"

    echo -e "${CLR_INFO}Выберите действие:${CLR_RESET}"
    read -r choice

    case $choice in
        1) install_trap ;;
        2) deploy_trap ;;
        3) create_operator ;;
        4) install_cli ;;
        5) check_logs ;;
        6) restart_node ;;
        7) remove_node ;;
        8) echo -e "${CLR_SUCCESS}Выход...${CLR_RESET}" && exit 0 ;;
        *) echo -e "${CLR_ERROR}Неверный выбор! Попробуйте снова.${CLR_RESET}" && show_menu ;;
    esac
}

# Запуск меню
show_menu









