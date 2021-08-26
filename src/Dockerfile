##
# Interact with the base image:
#   docker run --rm -it --entrypoint bash public.ecr.aws/lambda/ruby:2.7
#
##
# Interact with built container:
# docker run --rm -it --entrypoint bash mitre/serverless-inspec-lambda:latest
#
#
##
# Make requests to local container: (https://docs.aws.amazon.com/lambda/latest/dg/images-test.html)
# docker run -p 9000:8080 mitre/serverless-inspec-lambda:latest
# curl -XPOST "http://localhost:9000/2015-03-31/functions/function/invocations" -d '{}'
#
##
#
# Build the image
#   docker build -t mitre/serverless-inspec-lambda:latest .
#     OR
#   cd terraform/modules/inspec-lambda/; ./build-image.sh

##
# Use Ruby from AWS lambda ECR
#
# https://gallery.ecr.aws/lambda/ruby
#
FROM public.ecr.aws/lambda/ruby:2.7

##
# Copy over the function code
#
COPY lambda_function.rb Gemfile Gemfile.lock .ruby-version /var/task/

##
# Execute all commands within one RUN to minimize number of layers
#
RUN yum install -y gcc make gcc-c++ git unzip &&\
 # Initialize as a git repository so InSpec can run commands like `git remote show ...`
 git init &&\
 # Install gem dependencies with bundler
 bundle install --path vendor/bundle/ &&\
 # Accept the InSpec license
 bundle exec inspec --chef-license=accept &&\
 # Install k8s train plugin
 bundle exec inspec plugin install train-kubernetes &&\
 # Install awsssm train plugin
 bundle exec inspec plugin install train-awsssm &&\
 # Install the AWS CLI 
 curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" &&\
 unzip awscliv2.zip &&\
 ./aws/install &&\
 rm -rf awscliv2 awscliv2.zip aws &&\
 # Install the session-manager-plugin for the AWS CLI
 curl \
    "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" \
    -o "session-manager-plugin.rpm" &&\
 yum install -y session-manager-plugin.rpm &&\
 rm -rf session-manager-plugin.rpm &&\
 # Uninstall yum packages that will no longer be needed
 yum remove -y gcc make gcc-c++ unzip &&\
 # Clear out yum cache to save additional space
 yum clean all

##
# Set the handler
#
# https://docs.aws.amazon.com/lambda/latest/dg/images-create.html
#
CMD [ "lambda_function.lambda_handler" ]
