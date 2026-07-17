sudo apt update && sudo apt upgrade -y
sudo useradd --no-create-home --shell /bin/false prometheus
sudo mkdir /etc/prometheus /var/lib/prometheus
sudo chown prometheus:prometheus /etc/prometheus /var/lib/prometheus
cd /tmp
wget https://github.com/prometheus/prometheus/releases/download/v3.12.0/prometheus-3.12.0.linux-amd64.tar.gz
tar xvf prometheus-3.12.0.linux-amd64.tar.gz
sudo cp prometheus-3.12.0.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-3.12.0.linux-amd64/promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
sudo cp -r prometheus-3.12.0.linux-amd64/consoles /etc/prometheus/
sudo cp -r prometheus-3.12.0.linux-amd64/console_libraries /etc/prometheus/
sudo chown -R prometheus:prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries
sudo nano /etc/prometheus/prometheus.yml

```
global:
  scrape_interval: 15s # Интервал, по которому идет обращение к таргетам

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
```
sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
sudo nano /etc/systemd/system/prometheus.service
```
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
```
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

#Заходим на localhost:9090/metrics  

# Node exporter

sudo apt update && sudo apt upgrade -y
sudo useradd --no-create-home --shell /bin/false node_exporter
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
tar xvfz node_exporter-1.10.2.linux-amd64.tar.gz
sudo cp node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

sudo nano /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter

# Настройка Prometheus для сбора метрик с Node Exporter
sudo nano /etc/prometheus/prometheus.yml

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
  - job_name: 'node1'
    file_sd_configs:
      - files:
        - /etc/prometheus/target.json

rule_files:
  - "first_rules.yml"
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      - 'localhost:9093'


sudo nano /etc/prometheus/target.json

[
  {"labels": {"job": "node1"},
  "targets": ["localhost:9100"]
  },
  {"labels": {"job": "node2"},
  "targets": ["localhost:9100"]
  },
  {"labels": {"job": "node3"},
  "targets": ["localhost:9100"]
  }
]

sudo systemctl restart prometheus

# пробуем профильтровать в веб интерфейсе
node_load1{instance="localhost:9100", job="node_exporter"}[2m]


# Установка grafana
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https software-properties-common wget
# так как блокирется установка через apt, ставим через deb пакет и перекинем на ВМ
wget https://dl.grafana.com/grafana/release/13.1.0/grafana_13.1.0_28013217238_linux_amd64.deb
sudo systemctl daemon-reexec
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# подключение к victoria metrics
cd /tmp
wget https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v1.146.0/victoria-metrics-linux-amd64-v1.146.0.tar.gz
sudo cp victoria-metrics-prod /usr/local/bin/victoria-metrics
useradd --no-create-home --shell /bin/false victoriametrics
mkdir -p /var/lib/victoria-metrics
chown -R victoriametrics:victoriametrics /var/lib/victoria-metrics
nano /etc/systemd/system/victoria-metrics.service

[Unit]
Description=VictoriaMetrics
After=network.target

[Service]
Type=simple
User=victoriametrics
Group=victoriametrics
ExecStart=/usr/local/bin/victoria-metrics \
    --storageDataPath=/var/lib/victoria-metrics \
    --retentionPeriod=12 \
    --httpListenAddr=:8428
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target

systemctl daemon-reload
systemctl start victoria-metrics
systemctl enable victoria-metrics
systemctl status victoria-metrics
curl http://localhost:8428/api/v1/status/buildinfo

# заходим на prometheus
sudo nano /etc/prometheus/prometheus.yml

# и добавляем
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Отправка данных в VictoriaMetrics
remote_write:
  - url: "http://93.77.182.30:8428/api/v1/write"
    queue_config:
      max_samples_per_send: 10000
      batch_send_deadline: 5s
      max_shards: 30

systemctl restart prometheus.service

# alertmanager
wget https://github.com/prometheus/alertmanager/releases/download/v0.32.2/alertmanager-0.32.2.linux-amd64.tar.gz
sudo cp alertmanager amtool /usr/local/bin/

# Создаем пользователя и директории
sudo useradd --no-create-home --shell /bin/false alertmanager
sudo mkdir -p /etc/alertmanager /var/lib/alertmanager

# Копируем дефолтный конфиг
sudo cp alertmanager.yml /etc/alertmanager/

# Назначаем права
sudo chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager
sudo chown alertmanager:alertmanager /usr/local/bin/alertmanager /usr/local/bin/amtool

nano /etc/alertmanager/alertmanager.yml

global:
  resolve_timeout: 5m

# Маршрутизация алертов
route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'telegram-notifications'

  # Можно добавить дополнительные маршруты для разных алертов
  routes:
    - match:
        severity: critical
      receiver: 'telegram-critical'
      repeat_interval: 1h


receivers:
  - name: 'telegram-notifications'
    telegram_configs:
      - bot_token: '1234567890:ABCdefGHIjklMNOpqrsTUVwxyz'  # Токен вашего бота
        api_url: 'https://api.telegram.org'
        chat_id: 123456789  # ID вашего чата/канала
        parse_mode: 'HTML'
        message: |
          🔴 <b>{{ .Status | toUpper }}</b>
          
          <b>Алерт:</b> {{ .CommonLabels.alertname }}
          <b>Серьёзность:</b> {{ .CommonLabels.severity }}
          <b>Инстанс:</b> {{ .CommonLabels.instance }}
          
          <b>Описание:</b> {{ .CommonAnnotations.description }}
          
          <a href="http://localhost:9093/#/alerts">Открыть Alertmanager</a>

  - name: 'telegram-critical'
    telegram_configs:
      - bot_token: '1234567890:ABCdefGHIjklMNOpqrsTUVwxyz'
        api_url: 'https://api.telegram.org'
        chat_id: 123456789
        parse_mode: 'HTML'
        message: |
          🚨 <b>КРИТИЧЕСКИЙ АЛЕРТ!</b>
          
          <b>{{ .CommonLabels.alertname }}</b>
          {{ .CommonAnnotations.description }}

# Подавление дубликатов (опционально)
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']

sudo nano /etc/systemd/system/alertmanager.service

[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager/ \
    --web.listen-address=0.0.0.0:9093
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target

sudo systemctl daemon-reload
sudo systemctl start alertmanager
sudo systemctl enable alertmanager
sudo systemctl status alertmanager

# Подключаем к prometheus

nano /etc/prometheus/prometheus.yml

#Добавляем

# Подключение Alertmanager
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - localhost:9093

# Файлы с правилами алертов
rule_files:
  - "rules/*.yml"

sudo mkdir -p /etc/prometheus/rules
sudo chown -R prometheus:prometheus /etc/prometheus/rules

sudo nano /etc/prometheus/rules/alerts.yml


groups:
  - name: example_alerts
    rules:
      # Алерт: цель недоступна
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Инстанс {{ $labels.instance }} недоступен"
          description: "{{ $labels.instance }} job {{ $labels.job }} не отвечает более 1 минуты."

      # Алерт: высокая загрузка CPU
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокая загрузка CPU на {{ $labels.instance }}"
          description: "Загрузка CPU > 80% в течение 5 минут (текущее значение: {{ $value | humanize }}%)"

      # Алерт: мало места на диске
      - alert: LowDiskSpace
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Мало места на диске {{ $labels.instance }}"
          description: "Свободно менее 10% на {{ $labels.mountpoint }} (текущее значение: {{ $value | humanize }}%)"

      # Алерт: высокая загрузка памяти
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Высокое использование памяти на {{ $labels.instance }}"
          description: "Использование памяти > 90% (текущее значение: {{ $value | humanize }}%)"

# Проверяем синтаксис
promtool check rules /etc/prometheus/rules/alerts.yml

# И применяем конфигурации

sudo systemctl restart prometheus
sudo systemctl status prometheus
