This is a Megalisk deployable container.

It should contain a services yml file listing the desired git repos to pull and run.

You should be able to install this tiny package on EC2 and it pulls everything its needs and runs.

--

Summary of what this does,
just pulls docker images, or if given repo pulls and builds
takes each docker image and updates relevant nginx configs etc

idea is you pull this project, its what you deploy to EC2 or whatever
you just configure the apps you want to host via adding the repos (alt supply the ECR resource docker image)
(think how to simplify for users)
can build the app manually - do a megalisk publish to create your own ECR artifact AND deploy it to production
or just from this megalisk do megalisk build and it ensures all apps/services/apis build for the given environment
do megalisk run and it runs each app via docker compose defined by reading megalisk.yml for module additional configs

