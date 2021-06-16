set -xe

##
# ENV validation
#
if [ -z "$REPOSITORY_URL" ]; then
    echo '$REPOSITORY_URL is a required ENV variable!'
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo '$AWS_REGION is a required ENV variable!'
    exit 1
fi

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo '$AWS_ACCOUNT_ID is a required ENV variable!'
    exit 1
fi

if [ -z "$REPO_NAME" ]; then
    echo '$REPO_NAME is a required ENV variable!'
    exit 1
fi

if [ -z "$IMAGE_TAG" ]; then
    echo '$IMAGE_TAG is a required ENV variable!'
    exit 1
fi

echo "REPOSITORY_URL='$REPOSITORY_URL' AWS_REGION='$AWS_REGION' AWS_ACCOUNT_ID='$AWS_ACCOUNT_ID' REPO_NAME='$REPO_NAME' IMAGE_TAG='$IMAGE_TAG'"

##
# Variable creation
#
IMAGE_IDENTIFIER="$REPO_NAME:$IMAGE_TAG"
IMAGE="$REPOSITORY_URL:$IMAGE_TAG"
echo $IMAGE_IDENTIFIER
echo $IMAGE

##
# Log in to the AWS ECR registry
#
# https://awscli.amazonaws.com/v2/documentation/api/latest/reference/ecr/get-login-password.html
#
aws ecr get-login-password \
    --region $AWS_REGION \
| docker login \
    --username AWS \
    --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

##
# Re-tag the image to the identifier that will be pushed up to ECR
docker tag $IMAGE_IDENTIFIER $IMAGE

##
# Check the SHA of the local and remote images. Don't push if they are the same
#
LOCAL_SHA=$(docker images --no-trunc --quiet $IMAGE_IDENTIFIER | grep -oh 'sha256:[0-9,a-z]*')
REMOTE_SHA=$(aws ecr describe-images --repository-name $REPO_NAME --image-ids imageTag=$IMAGE_TAG --query 'imageDetails[0].imageDigest'| grep -oh 'sha256:[0-9,a-z]*' || echo 'image doesnt exist')
echo "LOCAL SHA:  $LOCAL_SHA"
echo "REMOTE SHA: $REMOTE_SHA"
if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    docker push $IMAGE
    sleep 60
else
    echo 'LOCAL AND REMOTE SHA values are identical. Skipping docker push.'
fi
