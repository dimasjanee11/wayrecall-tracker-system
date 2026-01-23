#!/bin/bash
# Первоначальная настройка сервера HP DL180 G6 для TrackerGPS

set -e

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  TrackerGPS - Initial Server Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Проверка что скрипт запускается на сервере
if [ "$HOSTNAME" != "freenaumen" ]; then
    echo -e "${YELLOW}⚠️  Этот скрипт должен запускаться на сервере!${NC}"
    echo -e "${YELLOW}   Выполните: ssh server 'bash -s' < test-stand/scripts/initial-setup.sh${NC}"
    exit 1
fi

echo -e "${GREEN}[1/8]${NC} Обновление системы..."
sudo apt update
sudo apt upgrade -y

echo ""
echo -e "${GREEN}[2/8]${NC} Установка базовых пакетов..."
sudo apt install -y \
    git \
    curl \
    wget \
    htop \
    ncdu \
    net-tools \
    vim \
    tmux \
    unzip

echo ""
echo -e "${GREEN}[3/8]${NC} Монтирование RAID массива..."
if ! mountpoint -q /mnt/raid; then
    sudo mkdir -p /mnt/raid
    sudo mount /dev/md0 /mnt/raid
    
    # Добавить в fstab если еще нет
    if ! grep -q "/dev/md0" /etc/fstab; then
        echo "/dev/md0 /mnt/raid ext4 defaults 0 2" | sudo tee -a /etc/fstab
    fi
    echo -e "${GREEN}✅ RAID массив смонтирован${NC}"
else
    echo -e "${GREEN}✅ RAID массив уже смонтирован${NC}"
fi

echo ""
echo -e "${GREEN}[4/8]${NC} Создание структуры директорий..."
sudo mkdir -p /mnt/raid/docker
sudo mkdir -p /mnt/raid/docker-data/{postgres,redis,kafka,zookeeper,prometheus,grafana}
sudo mkdir -p /mnt/raid/backups
sudo mkdir -p /mnt/raid/logs
sudo chown -R $USER:$USER /mnt/raid

echo ""
echo -e "${GREEN}[5/8]${NC} Установка Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    sudo usermod -aG docker $USER
    echo -e "${GREEN}✅ Docker установлен${NC}"
else
    echo -e "${GREEN}✅ Docker уже установлен${NC}"
fi

echo ""
echo -e "${GREEN}[6/8]${NC} Настройка Docker для RAID..."
sudo systemctl stop docker || true

# Создать конфигурацию Docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "data-root": "/mnt/raid/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-address-pools": [
    {
      "base": "172.18.0.0/16",
      "size": 24
    }
  ]
}
EOF

# Перенести существующие данные если есть
if [ -d "/var/lib/docker" ] && [ "$(ls -A /var/lib/docker)" ]; then
    echo -e "${YELLOW}Перенос существующих данных Docker...${NC}"
    sudo rsync -avz /var/lib/docker/ /mnt/raid/docker/
fi

sudo systemctl start docker
sudo systemctl enable docker

echo ""
echo -e "${GREEN}[7/8]${NC} Настройка firewall..."
if command -v ufw &> /dev/null; then
    sudo ufw --force enable
    sudo ufw allow 22/tcp comment 'SSH'
    sudo ufw allow 3000/tcp comment 'Grafana'
    sudo ufw allow 9090/tcp comment 'Prometheus'
    sudo ufw allow from 192.168.1.0/24 to any port 5432 comment 'PostgreSQL local'
    sudo ufw allow from 192.168.1.0/24 to any port 6379 comment 'Redis local'
    sudo ufw allow from 192.168.1.0/24 to any port 9092 comment 'Kafka local'
    echo -e "${GREEN}✅ Firewall настроен${NC}"
else
    echo -e "${YELLOW}⚠️  UFW не установлен${NC}"
fi

echo ""
echo -e "${GREEN}[8/8]${NC} Клонирование репозитория..."
mkdir -p ~/projects
cd ~/projects

if [ ! -d "wayrecall-tracker-system" ]; then
    git clone --recursive https://github.com/dimasjanee11/wayrecall-tracker-system.git
    cd wayrecall-tracker-system
    echo -e "${GREEN}✅ Репозиторий клонирован${NC}"
else
    cd wayrecall-tracker-system
    git pull
    git submodule update --init --recursive
    echo -e "${GREEN}✅ Репозиторий обновлен${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ Первоначальная настройка завершена!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Следующие шаги:${NC}"
echo -e "  1. Настройте .env файл:"
echo -e "     ${BLUE}cd ~/projects/wayrecall-tracker-system${NC}"
echo -e "     ${BLUE}cp test-stand/.env.example test-stand/.env${NC}"
echo -e "     ${BLUE}nano test-stand/.env${NC}"
echo -e ""
echo -e "  2. Запустите развертывание:"
echo -e "     ${BLUE}bash test-stand/scripts/deploy.sh${NC}"
echo -e ""
echo -e "${YELLOW}⚠️  ВАЖНО: Перелогиньтесь для применения прав Docker группы!${NC}"
echo -e "   ${BLUE}exit${NC} и затем ${BLUE}ssh server${NC}"
