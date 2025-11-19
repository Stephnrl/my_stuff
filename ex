name: Deploy Infrastructure and Configure

on: [workflow_dispatch]

jobs:
  terraform:
    runs-on: ubuntu-latest
    outputs:
      vm_ip: ${{ steps.tf_output.outputs.vm_ip }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Terraform Apply
        # ... your terraform steps ...
        
      - name: Get VM IP
        id: tf_output
        run: |
          echo "vm_ip=$(terraform output -raw vm_ip)" >> $GITHUB_OUTPUT

  configure:
    needs: terraform
    runs-on: ubuntu-latest
    steps:
      - name: Run Ansible Configuration
        uses: your-org/ansible-action@v1
        with:
          playbook: 'playbooks/day1-setup.yml'
          inventory: '${{ needs.terraform.outputs.vm_ip }},'
          ansible-repo: 'your-org/ansible-playbooks'
          ansible-repo-token: ${{ secrets.ANSIBLE_REPO_TOKEN }}
          collections: 'community.general,ansible.posix'
          tags: 'elastic,defender'
          ssh-private-key: ${{ secrets.SSH_PRIVATE_KEY }}
          extra-vars: |
            {
              "elastic_version": "8.11.0",
              "defender_tenant_id": "${{ secrets.DEFENDER_TENANT }}"
            }
