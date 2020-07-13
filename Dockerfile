FROM node:alpine3.12

# our workdir in container
WORKDIR /app
# copy the source files to container
COPY app/ .
# install the node packages
RUN npm install
# build the app
RUN npm run build
# run the app
CMD [ "npm", "start" ]
