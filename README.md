
I received an application (Next.js, React) and a few tasks to accomplish.

The application is in `app` directory. First thing I needed to do, was to rename all javascript files from `.j_` to `.js` (probably the email server is the culprit for it)


### Prepare the local machine with the needed tools (I used CentOS 7)

~~~
sudo yum install -y gcc-c++ make git python3
sudo pip install awscli
sudo curl -sL https://rpm.nodesource.com/setup_12.x | sudo -E bash -
sudo yum install nodejs
sudo pip3 install awsebcli
sudo yum install docker
systemctl start docker
systemctl enable docker
~~~

### Configure AWS CLI on local machine

~~~
$ aws configure
AWS Access Key ID [None]: AKIASADADDADADADDA
AWS Secret Access Key [None]: jkahdfjahdjahdjajkdhajdhajhdjahdjad
Default region name [None]: us-east-1
Default output format [None]: json
~~~

### Deploy the application to Elastic Beanstalk

Push everything to GIT
~~~
cd app
git config --global user.email "cool-name@gmail.com"
git config --global user.name "Cool Name"
git add .
git commit -m "Initial app import"
~~~

Set default values for Elastic Beanstalk application
~~~
eb init
~~~

Customize the EB application for our use
~~~
$ mkdir .ebextensions

$ cd .ebextensions

cat << EOF >> 01_appconfig.config
option_settings:
  aws:elasticbeanstalk:application:environment:
    PORT: 3000
    NODE_ENV: production
EOF

cat << EOF >> 02_nodecommand.config 
option_settings:
  aws:elasticbeanstalk:container:nodejs:
    NodeCommand: "npm start"
EOF
~~~

Add a specific port (expected by Beanstalk) to our `next start` command
~~~ 
{
  "name": "challenge3",
  "scripts": {
    "dev": "next",
    "build": "next build",
    "start": "next start -p $PORT"
  },
  "dependencies": {
    "axios": "^0.18.0",
    "next": "^8.0.3",
    "react": "^16.8.4",
    "react-dom": "^16.8.4"
  }
}
~~~

Create an environment
~~~
eb create my-app-env
~~~

**Note:** wait a few minutes to have the environment ready otherwise the deployment done in the next step will not work

Deploy the application
~~~
eb deploy
~~~

Get the endpoint to access the deployed app
~~~
aws elasticbeanstalk describe-environments --environment-names my-app-env  --query "Environments[*].CNAME" --output text
~~~

### Restrict the access to our web app only from a certain CIDR range

**Note** the security group ids should be replaced with the ones fron the command output

Get the security group id of the created load balancer
~~~
aws ec2 describe-security-groups \
    --filters Name=tag:aws:cloudformation:logical-id,Values=AWSEBLoadBalancerSecurityGroup \
    --query "SecurityGroups[*].{Name:GroupName,ID:GroupId}"
~~~

Describe the security group to see the current ingress/egress
~~~
aws ec2 describe-security-groups --group-ids sg-0ba5315d4ca1515b8
~~~

Allow access to port 80 only from a CIDR range (e.g. 208.2.80.25/24)
~~~
aws ec2 authorize-security-group-ingress \
    --group-id sg-0ba5315d4ca1515b8 \
    --protocol tcp \
    --port 80 \
    --cidr 208.2.80.25/24
~~~

Remove the rule which allow acces to all from security group:
~~~
aws ec2 revoke-security-group-ingress \
    --group-id sg-0ba5315d4ca1515b8 \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0
~~~

**Note:** run `eb terminate` to terminate the Beanstalk environment. The S3 bucket used to store the zipped app version will not be removed, please remove it using AWS console or `aws s3 rb s3://bucket-name --force`, of course after one gets the bucket name with `aws s3 ls`


### Preparation for next deployents: Build a docker image with the app and push it to ECR

One level up, where the Dockerfile is
~~~
cd ..
~~~

Modify the `next start` command in our `package.json` file to listen not only on localhost and to listen on port 80
~~~
{
  "name": "challenge3",
  "scripts": {
    "dev": "next",
    "build": "next build",
    "start": "next start --hostname 0.0.0.0 -p 80"
  },
  "dependencies": {
    "axios": "^0.18.0",
    "next": "^8.0.3",
    "react": "^16.8.4",
    "react-dom": "^16.8.4"
  }
}
~~~

Create a repo for our docker image on ECR
~~~
$ aws ecr create-repository --repository-name app
{
    "repository": {
        "repositoryUri": "301236818234.dkr.ecr.us-east-1.amazonaws.com/app", 
        "imageScanningConfiguration": {
            "scanOnPush": false
        }, 
        "registryId": "301236818234", 
        "imageTagMutability": "MUTABLE", 
        "repositoryArn": "arn:aws:ecr:us-east-1:301236818234:repository/app", 
        "repositoryName": "app", 
        "createdAt": 1594572088.0
    }
}
~~~

Build the docker image:
~~~
docker build -t 185513101483.dkr.ecr.us-east-1.amazonaws.com/app:v1.0 .
~~~

Get a login token to be able to push to ECR
~~~
$(aws ecr get-login --no-include-email)
Login Succeeded
~~~

Push the docker image to ECR
~~~
docker push 185513101483.dkr.ecr.us-east-1.amazonaws.com/app:v1.0
~~~

### Deployment to ECS + Fargate

Install ecs-cli:
~~~
sudo curl -o /usr/local/bin/ecs-cli https://amazon-ecs-cli.s3.amazonaws.com/ecs-cli-linux-amd64-latest
sudo chmod 755 /usr/local/bin/ecs-cli
cd ecs-fargate
aws iam --region us-east-1 create-role --role-name ecsTaskExecutionRole --assume-role-policy-document file://task-execution-assume-role.json
aws iam --region us-east-1 attach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
ecs-cli configure --cluster app --default-launch-type FARGATE --config-name app --region us-east-1
# add your access-key and secret-key in the next command
ecs-cli configure profile --access-key AKIASWMLRJCVYVHLP3GP --secret-key aeg9zSHKMxAIPvXWp2suT219Qaow/3qfaHKJHj/n --profile-name app-profile
~~~

Next command may take a few minutes to complete as the resources are created
~~~
ecs-cli up --cluster-config app --ecs-profile app-profile
~~~

VPC id is from the output of the above command
~~~
aws ec2 describe-security-groups --filters Name=vpc-id,Values=vpc-007e6f41fb6cc3797 --region us-east-1
~~~

Security group id taken from above output
~~~
aws ec2 authorize-security-group-ingress --group-id sg-0cd39303265439b5e --protocol tcp --port 80 --cidr 0.0.0.0/0 --region us-east-1
~~~

Start the app
~~~
ecs-cli compose --project-name app service up --create-log-groups --cluster-config app --ecs-profile app-profile
~~~

Check the running containers (Get the IP and port and add it to your browser to see the deployed app)
~~~
ecs-cli compose --project-name app service ps --cluster-config app --ecs-profile app-profile
~~~

Check the container logs
~~~
ecs-cli logs --task-id 574c665a-a14d-4cd9-b80d-2907b4eb783e --follow --cluster-config app --ecs-profile app-profile
~~~

Shutdown the app:
~~~
ecs-cli compose --project-name app service down --cluster-config app --ecs-profile app-profile
~~~

### Deployment to EKS

#### Create an EKS cluster with eksctl if you don't have yet:

Install eksctl
~~~
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
sudo chmod 755 /usr/local/bin/eksctl
~~~

Create the eks cluster
~~~
eksctl create cluster \
  --name my-cluster \
  --version 1.16 \
  --without-nodegroup

eksctl create nodegroup \
  --cluster my-cluster \
  --version auto \
  --name standard-workers \
  --node-type t3.medium \
  --node-ami auto \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4
~~~

#### Deploy the app:

Create a new namespace for app to be deployed:
~~~
kubectl create namespace app-namespace
~~~

Deploy the app:
~~~
cd eks
kubectl apply -f deploy-app-on-eks.yml
~~~

**Note:** will take a few minutes until the load balancer is reachable and the EKS workers to be inService

Get the loadbalancer name with: 
~~~
echo `kubectl -n app-namespace get svc app-service -o jsonpath={'.status'.loadBalancer.ingress[*].hostname}`
~~~

Use the loadbalancer name in your browser to see the deployed app

### Issues 

- outdated node js packages containing vulenrabilities
- inline css isn’t the best way to implement css in app
