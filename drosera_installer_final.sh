#!/bin/bash

# Цвета для оформления
CLR_SUCCESS='\033[1;32m'
CLR_INFO='\033[1;34m'
CLR_WARNING='\033[1;33m'
CLR_ERROR='\033[1;31m'
CLR_RESET='\033[0m'

function show_logo() {
    echo -e "${CLR_INFO}**********************************************************${CLR_RESET}"
    echo -e "${CLR_SUCCESS}      Добро пожаловать в установочный скрипт Drosera       ${CLR_RESET}"
    echo -e "${CLR_INFO}**********************************************************${CLR_RESET}"
    curl -s https://raw.githubusercontent.com/profitnoders/Profit_Nodes/refs/heads/main/logo_new.sh | bash
}

function install_dependencies() {
    echo -e "${CLR_INFO}▶ Установка зависимостей...${CLR_RESET}"
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt install -y curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip

    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove -y $pkg; done

    sudo apt-get install -y ca-certificates gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo       "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu       $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |       sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl start docker
    sudo docker run hello-world
}

function install_drosera_foundry_bun() {
    echo -e "${CLR_INFO}▶ Установка Drosera CLI...${CLR_RESET}"
    curl -L https://app.drosera.io/install | bash
    source ~/.bashrc
    droseraup

    echo -e "${CLR_INFO}▶ Установка Foundry CLI...${CLR_RESET}"
    curl -L https://foundry.paradigm.xyz | bash
    source ~/.bashrc
    foundryup

    echo -e "${CLR_INFO}▶ Установка Bun...${CLR_RESET}"
    curl -fsSL https://bun.sh/install | bash
    source ~/.bashrc
}

function deploy_trap() {
    mkdir -p ~/my-drosera-trap && cd ~/my-drosera-trap
    read -p "Введите ваш Github email: " GITHUB_EMAIL
    read -p "Введите ваш Github username: " GITHUB_USERNAME
    git config --global user.email "$GITHUB_EMAIL"
    git config --global user.name "$GITHUB_USERNAME"

    forge init -t drosera-network/trap-foundry-template
    bun install
    forge build

    read -p "Введите ваш приватный ключ от EVM кошелька: " PRIV_KEY
    DROSERA_PRIVATE_KEY=$PRIV_KEY drosera apply

    echo -e "${CLR_WARNING}▶ Обязательно выполните действие Send Bloom Boost в дашборде${CLR_RESET}"
    echo -e "${CLR_INFO}▶ После этого вручную выполните команду: drosera dryrun${CLR_RESET}"
}

function create_operator() {
    cd ~/my-drosera-trap
    read -p "Введите публичный адрес кошелька оператора: " WALLET
    sed -i '/^private_trap/d' drosera.toml
    sed -i '/^whitelist/d' drosera.toml
    echo -e "private_trap = true
whitelist = ["$WALLET"]" >> drosera.toml

    read -p "Введите ваш приватный ключ от EVM кошелька: " PRIV_KEY
    DROSERA_PRIVATE_KEY=$PRIV_KEY drosera apply
}

function install_cli_and_service() {
    cd ~
    curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    sudo cp drosera-operator /usr/bin

    read -p "Введите приватный ключ от EVM кошелька: " PRIV_KEY
    drosera-operator register --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com --eth-private-key "$PRIV_KEY"

    read -p "Введите внешний IP сервера: " IP_ADDRESS

    sudo bash -c "cat <<EOF > /etc/systemd/system/drosera.service
[Unit]
Description=Drosera Node Service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which drosera-operator) node --db-file-path \$HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \
  --eth-rpc-url https://ethereum-holesky-rpc.publicnode.com \
  --eth-backup-rpc-url https://1rpc.io/holesky \
  --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
  --eth-private-key $PRIV_KEY \
  --listen-address 0.0.0.0 \
  --network-external-p2p-address $IP_ADDRESS \
  --disable-dnr-confirmation true
Restart=always
RestartSec=15
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF"

    sudo ufw allow 31313/tcp
    sudo ufw allow 31314/tcp
    sudo ufw --force enable

    sudo systemctl daemon-reload
    sudo systemctl enable drosera
    sudo systemctl start drosera
}

function view_logs() {
    journalctl -u drosera -f
}

function restart_node() {
    sudo systemctl restart drosera
}

function remove_node() {
    read -p "⚠ Удалить ноду Drosera? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        sudo systemctl stop drosera
        sudo systemctl disable drosera
        sudo rm -f /etc/systemd/system/drosera.service
        sudo systemctl daemon-reload
        rm -rf ~/.drosera ~/.drosera.db ~/.foundry ~/.bun ~/my-drosera-trap ~/drosera-operator*
        echo -e "${CLR_SUCCESS}✅ Нода удалена.${CLR_RESET}"
    else
        echo -e "${CLR_INFO}▶ Удаление отменено.${CLR_RESET}"
    fi
}

function install_node() {
    show_logo
    install_dependencies
    install_drosera_foundry_bun
    deploy_trap
    create_operator
    install_cli_and_service
    view_logs
}

# Меню
function show_menu() {
    show_logo
    echo -e "${CLR_INFO}Выберите действие:${CLR_RESET}"
    echo -e "${CLR_SUCCESS}1) 🚀 Установить ноду Drosera${CLR_RESET}"
    echo -e "${CLR_SUCCESS}2) 🔁 Перезапуск ноды${CLR_RESET}"
    echo -e "${CLR_SUCCESS}3) 📜 Просмотр логов${CLR_RESET}"
    echo -e "${CLR_WARNING}4) 🗑 Удалить ноду${CLR_RESET}"
    echo -e "${CLR_ERROR}5) ❌ Выйти${CLR_RESET}"

    read -p "Введите номер: " choice
    case $choice in
        1) install_node ;;
        2) restart_node ;;
        3) view_logs ;;
        4) remove_node ;;
        5) echo -e "${CLR_INFO}Выход...${CLR_RESET}" && exit ;;
        *) echo -e "${CLR_ERROR}Неверный выбор${CLR_RESET}" && show_menu ;;
    esac
}

show_menu
