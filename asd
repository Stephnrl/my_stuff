{
  "version": "1.0.0",
  "channelId": "VisualStudio.{{ vs_version_major }}.Release",
  "product": {
    "id": "Microsoft.VisualStudio.Product.BuildTools"
  },
  "installChannelUri": ".\\ChannelManifest.json",
  "installCatalogUri": ".\\Catalog.json",
  "add": [
{% set all_items = vs_workloads + vs_components %}
{% for item in all_items %}
    { "id": "{{ item }}"{{ "" if loop.last else "," }} }
{% endfor %}
  ],
  "addProductLang": [
    "en-US"
  ]
}
