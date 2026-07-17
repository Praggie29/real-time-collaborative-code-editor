# 🚀 Deployment Guide — Collaborative Editor

## Table of Contents
- [Docker (Local)](#docker-local)
- [AWS Setup (One-Time)](#aws-setup-one-time)
- [AWS Deploy](#aws-deploy)

---

## Docker (Local)

### Prerequisites
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running

### Option 1: Docker Compose (Recommended)
```bash
# Build and start
docker-compose up --build

# Run in background
docker-compose up --build -d

# Stop
docker-compose down
```

### Option 2: Manual Docker
```bash
# Build
docker build -t collab-editor .

# Run
docker run -p 3000:3000 collab-editor

# Verify
curl http://localhost:3000/health
```

Open **http://localhost:3000** in your browser.

---

## AWS Setup (One-Time)

### Prerequisites
- AWS account with admin access
- [AWS CLI](https://aws.amazon.com/cli/) installed (`aws --version`)
- AWS CLI configured (`aws configure` — enter your access key, secret, region)

### Step 1: Create ECR Repository
```bash
aws ecr create-repository \
    --repository-name collab-editor \
    --region ap-south-1
```

### Step 2: Create CloudWatch Log Group
```bash
aws logs create-log-group \
    --log-group-name /ecs/collab-editor \
    --region ap-south-1
```

### Step 3: Create ECS Cluster
```bash
aws ecs create-cluster \
    --cluster-name collab-editor-cluster \
    --region ap-south-1
```

### Step 4: Create IAM Roles

**a) ECS Task Execution Role** (allows ECS to pull images from ECR):
```bash
# Create the role
aws iam create-role \
    --role-name ecsTaskExecutionRole \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ecs-tasks.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }'

# Attach the managed policy
aws iam attach-role-policy \
    --role-name ecsTaskExecutionRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

**b) ECS Task Role** (permissions for your app — basic for now):
```bash
aws iam create-role \
    --role-name ecsTaskRole \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ecs-tasks.amazonaws.com"},
        "Action": "sts:AssumeRole"
      }]
    }'
```

### Step 5: Update Configuration

Edit `aws/task-definition.json` and `deploy.sh`:
- Replace `<AWS_ACCOUNT_ID>` with your 12-digit AWS account ID
- Replace `<AWS_REGION>` with your region (e.g., `ap-south-1`)
- In `deploy.sh`, set `AWS_ACCOUNT_ID="123456789012"`

### Step 6: Register Task Definition
```bash
aws ecs register-task-definition \
    --cli-input-json file://aws/task-definition.json \
    --region ap-south-1
```

### Step 7: Create Security Group
```bash
# Get your default VPC ID
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" --output text --region ap-south-1
# → returns: vpc-xxxxxxxx

# Create security group
aws ec2 create-security-group \
    --group-name collab-editor-sg \
    --description "Collab Editor ECS Security Group" \
    --vpc-id vpc-xxxxxxxx \
    --region ap-south-1
# → returns: sg-xxxxxxxx

# Allow inbound traffic on port 3000
aws ec2 authorize-security-group-ingress \
    --group-id sg-xxxxxxxx \
    --protocol tcp \
    --port 3000 \
    --cidr 0.0.0.0/0 \
    --region ap-south-1
```

### Step 8: Create ECS Service
```bash
# Get a public subnet ID
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=vpc-xxxxxxxx" \
    --query "Subnets[0].SubnetId" --output text --region ap-south-1
# → returns: subnet-xxxxxxxx

# Create the service
aws ecs create-service \
    --cluster collab-editor-cluster \
    --service-name collab-editor-service \
    --task-definition collab-editor-task \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration '{
      "awsvpcConfiguration": {
        "subnets": ["subnet-xxxxxxxx"],
        "securityGroups": ["sg-xxxxxxxx"],
        "assignPublicIp": "ENABLED"
      }
    }' \
    --region ap-south-1
```

---

## AWS Deploy

After the one-time setup, deploy with a single command:

### Using the deploy script
```bash
# Make executable (first time only)
chmod +x deploy.sh

# Deploy!
./deploy.sh
```

### Manual deploy
```bash
# 1. Login to ECR
aws ecr get-login-password --region ap-south-1 | \
    docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com

# 2. Build
docker build -t collab-editor .

# 3. Tag
docker tag collab-editor:latest <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/collab-editor:latest

# 4. Push
docker push <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/collab-editor:latest

# 5. Update ECS (force new deployment to pull latest image)
aws ecs update-service \
    --cluster collab-editor-cluster \
    --service collab-editor-service \
    --force-new-deployment \
    --region ap-south-1
```

### Find your app's public IP
```bash
# Get the task ARN
TASK_ARN=$(aws ecs list-tasks \
    --cluster collab-editor-cluster \
    --service-name collab-editor-service \
    --query "taskArns[0]" --output text --region ap-south-1)

# Get the ENI (network interface) ID
ENI_ID=$(aws ecs describe-tasks \
    --cluster collab-editor-cluster \
    --tasks $TASK_ARN \
    --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
    --output text --region ap-south-1)

# Get the public IP
aws ec2 describe-network-interfaces \
    --network-interface-ids $ENI_ID \
    --query "NetworkInterfaces[0].Association.PublicIp" \
    --output text --region ap-south-1
```

Then open: `http://<PUBLIC_IP>:3000`

---

## Architecture

```
┌─────────────────────────────────────────┐
│              AWS Cloud                  │
│  ┌───────────────────────────────────┐  │
│  │         ECS Fargate Cluster       │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │    Docker Container         │  │  │
│  │  │  ┌───────────────────────┐  │  │  │
│  │  │  │   Express Server      │  │  │  │
│  │  │  │   (port 3000)         │  │  │  │
│  │  │  │                       │  │  │  │
│  │  │  │  ├─ /public (React)   │  │  │  │
│  │  │  │  ├─ /health           │  │  │  │
│  │  │  │  └─ Socket.IO + Yjs   │  │  │  │
│  │  │  └───────────────────────┘  │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
│                                         │
│  ECR Repository: collab-editor          │
│  CloudWatch Logs: /ecs/collab-editor    │
└─────────────────────────────────────────┘
```
