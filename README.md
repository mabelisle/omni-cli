  ## Omni-cli
  omni-cli:
   build: ./build/omni-cli
   container_name: omni-cli
   networks:
     intranet:
       ipv4_address: 10.0.100.88
   volumes:
     - omni-cli_data:/data
     - omni-cli_config:/config
   restart: unless-stopped