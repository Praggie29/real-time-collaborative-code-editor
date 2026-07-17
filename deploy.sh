#!/bin/bash

# =============================================================================
# Collaborative Editor - AWS Deployment Script
# =============================================================================
# Usage: ./deploy.sh
#
# Prerequisites:
#   1. AWS CLI installed and configured (aws configure)
#   2. Docker installed and running
#   3. ECR repository created
#   4. ECS cluster and service created
# =============================================================================

set -e

# ---- CONFIGURE THESE ----
AWS_REGION="ap-south-1"
AWS_ACCOUNT_ID="YOUR_AWS_ACCOUNT_ID"
ECR_REPO_NAME="collab-editor"
ECS_CLUSTER_NAME="collab-editor-cluster"
ECS_SERVICE_NAME="collab-editor-service"
# --------------------------

ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
IMAGE_TAG="latest"

echo "============================================"
echo "  Collaborative Editor - AWS Deployment"
echo "============================================"

# Step 1: Login to ECR
echo ""
echo "[1/4] Logging in to Amazon ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Step 2: Build Docker image
echo ""
echo "[2/4] Building Docker image..."
docker build -t "${ECR_REPO_NAME}:${IMAGE_TAG}" .

# Step 3: Tag and push to ECR
echo ""
echo "[3/4] Pushing image to ECR..."
docker tag "${ECR_REPO_NAME}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
docker push "${ECR_URI}:${IMAGE_TAG}"

# Step 4: Update ECS service (force new deployment)
echo ""
echo "[4/4] Updating ECS service..."
aws ecs update-service \
    --cluster "${ECS_CLUSTER_NAME}" \
    --service "${ECS_SERVICE_NAME}" \
    --force-new-deployment \
    --region "${AWS_REGION}"

echo ""
echo "============================================"
echo "  Deployment initiated successfully!"
echo "  ECS will pull the new image and restart."
echo "  Monitor: https://${AWS_REGION}.console.aws.amazon.com/ecs"
echo "============================================"
