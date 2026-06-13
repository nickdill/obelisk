To DO: make this more thorough

For now

Add modules to the obelisk.yml
domain is required and must match in order for nginx to port traffic to the given module
port is forced onto the docker service
so if oblisk runs at port 9100, and module dev runs at domain dev.localhost at port 9101, dont go to dev.localhost:9101, go to dev.localhost:9100 nginx gets the initial traffic, see domain, routes to the server on port 9101 for you, boom serving the app.
