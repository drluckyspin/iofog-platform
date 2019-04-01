import subprocess

def bash_cmd(bashCommand):
    process = subprocess.Popen(bashCommand.split(), stdout=subprocess.PIPE)
    output, error = process.communicate()

    return output

DOCKER_IMAGES = [
   "armhf/httpd" "mongo" "gateway" "image-service" "device-service" "detection-service" "command-service" "livestream" "user-service" "video-service" "web-service" ]

def setup_user():
    bash_cmd("iofog-controller user add --email 'test@edgeworx.io' --first-name 'Test' --last-name 'Name' --password 'test1234'")
    command = "iofog-controller user list | grep id | awk 'NR==1 {print $2}'"
    user = bash_cmd(command).decode()
    user = user[:-1]

    return user

def main():
    user = setup_user()
    prov_tokens = []
    catalog_ids = []

    for i in range(len(DOCKER_IMAGES)):
        docker_image_name = "edgeworx/jrc-1-{}".format(DOCKER_IMAGES[i])
        tag = "release"
        if( i < 2 ):
            docker_image_name=DOCKER_IMAGES[i]
            tag = "latest"

        command = "iofog-controller catalog add --name {} --x86-image {}:{} --registry-id 1 --user-id \
                                {} --category 'some-category'".format(DOCKER_IMAGES[i], docker_image_name, tag, user)


        catalog_id = bash_cmd(command).decode()
        catalog_id = catalog_id.split(":", 1)[1][:-2]
        catalog_ids.append(catalog_id)

main()