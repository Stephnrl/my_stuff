conditional_groups:
  ghes_servers: "'ghes' in name | lower or tags.get('publisher', '') == 'GitHub'"
  backup_servers: "image.publisher is defined and image.publisher == 'Canonical' and ('ghes' in name | lower or 'github' in name | lower)"
