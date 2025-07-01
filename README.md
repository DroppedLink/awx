# AWX Enterprise-Style Dev/Lab Repository

## Structure
```
awx/
├── playbooks/                # All playbooks (migrated from repo root)
├── roles/                    # Roles (refactor common logic here)
├── group_vars/               # Group variables (for inventory groups)
├── host_vars/                # Host-specific variables
├── inventory/                # Dynamic/static inventory files
│   └── dynamic_inventory.json
├── files/                    # Static files for playbooks/roles
├── templates/                # Jinja2 templates for playbooks/roles
├── requirements.yml          # Ansible Galaxy role/collection requirements
├── requirements.txt          # Python requirements
├── setup.sh                  # Setup script
├── survey_patch_job.yaml     # Example AWX survey YAML
├── workflow_patch_and_reboot.yaml   # Patch & Reboot workflow template
├── workflow_zabbix_maintenance.yaml # Zabbix Maintenance workflow template
└── README.md                 # This file
```

## AWX Survey Example
- See `survey_patch_job.yaml` for a sample survey to prompt users for environment, patch type, and reboot.
- In AWX: Edit a Job Template → Surveys tab → Import or add questions as shown in the YAML.

## Workflow Templates
- `workflow_patch_and_reboot.yaml`: Chains patching, optional reboot, and health verification jobs.
- `workflow_zabbix_maintenance.yaml`: Chains Zabbix maintenance, backup, and restart jobs.
- In AWX: Templates → Add → Workflow Template → Import YAML or create nodes as described.

## Dynamic Inventory Scan
- A Python script scans 10.0.0.0/24 for SSH/WinRM, using provided credentials.
- Output: `/root/awx/inventory/dynamic_inventory.json` (AWX-compatible inventory file).
- To use: Import this file as a custom inventory source in AWX.

## Credentials
- Linux: `swhite/Numbers123!!` (sudo) or `root/Numbers123!!` (direct)
- Windows: `Administrator/Numbers123!!` or `swhite/Numbers123!!`

## Next Steps
- Refactor playbooks into roles for reusability.
- Add more workflow templates as needed.
- Use dynamic inventory for scalable host management.
- Use surveys for interactive job launches.

---
This repo is now structured for real-world AWX enterprise workflows, ready for Dev/Lab use!
