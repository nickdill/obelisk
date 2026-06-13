Given how this application works, it dynamically runs a list of docker images supplied in the config.

For production deployments, this means the server must authenticate and pull potentially private images, wait for them to download, then run them.

Alternatively we create an image of that environment that already has them pulled - then our production environment just pulls the one image and its run runs all its child images?

Im not entirely sure, does docker work like that? At a certain point should we be considering k8s or something else? Is there a better way?
