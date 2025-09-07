#!/bin/bash
set -e

# Force Ansible to use colors even with tee
export ANSIBLE_FORCE_COLOR=1
export ANSIBLE_STDOUT_CALLBACK=yaml

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="logs/deployment_${TIMESTAMP}.log"
mkdir -p logs

echo "=== Ansible Monitoring Stack Deployment (Native Rust Exporters) ===" | tee "$LOG_FILE"

echo "Installing required Ansible collections..." | tee -a "$LOG_FILE"
ansible-galaxy collection install community.docker --force 2>&1 | tee -a "$LOG_FILE"

echo "Testing connectivity to all hosts..." | tee -a "$LOG_FILE"
ansible all -i hosts.ini -m ping 2>&1 | tee -a "$LOG_FILE"

echo "Starting deployment..." | tee -a "$LOG_FILE"
ansible-playbook -i hosts.ini site.yml -v 2>&1 | tee -a "$LOG_FILE"

echo "=== Deployment Complete ===" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Access URLs:" | tee -a "$LOG_FILE"
echo "- Grafana:    http://10.10.3.24:33331 (admin/monitoring123)" | tee -a "$LOG_FILE"
echo "- Prometheus: http://10.10.3.24:39091" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Exporter endpoints on slave_node_01:" | tee -a "$LOG_FILE"
echo "- GPU Process (Native): http://10.6.254.75:9200/metrics" | tee -a "$LOG_FILE"
echo "- Disk Usage (Native):  http://10.6.254.75:9201/metrics" | tee -a "$LOG_FILE"
echo "- Tmp Files (Native):   http://10.6.254.75:9202/metrics" | tee -a "$LOG_FILE"
echo "- Node (Docker):        http://10.6.254.75:39100/metrics" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Service Management Commands:" | tee -a "$LOG_FILE"
echo "- Check status: sudo systemctl status cmstack-{gpu,disk,tmp}-exporter" | tee -a "$LOG_FILE"
echo "- View logs:    sudo journalctl -u cmstack-gpu-exporter -f" | tee -a "$LOG_FILE"
echo "- Restart:      sudo systemctl restart cmstack-gpu-exporter" | tee -a "$LOG_FILE"

echo ""
echo "Log saved to: $LOG_FILE"