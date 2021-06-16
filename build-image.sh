VERSION=$(cat './version')

docker build -t mitre/serverless-inspec-lambda:$VERSION ./src/
docker tag mitre/serverless-inspec-lambda:$VERSION mitre/serverless-inspec-lambda:latest

# docker save mitre/serverless-inspec-lambda:$VERSION > serverless-inspec-lambda.tar
