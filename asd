conditional_groups:
  ghes_servers: "'ghes' in name | lower or 'github' in name | lower"
  backup_servers: "'backup' in name | lower and ('ghes' in name | lower or 'github' in name | lower)"
