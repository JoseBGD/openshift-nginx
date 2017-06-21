CONTEXT = nginxinc
VERSION = 1.13.1
IMAGE_NAME = openshift-nginx
REGISTRY = docker-registry.default.svc.cluster.local
OC_USER=developer
OC_PASS=developer

# Allow user to pass in OS build options
ifeq ($(TARGET),rhel7)
	DFILE := Dockerfile.${TARGET}
else
	TARGET := centos7
	DFILE := Dockerfile
endif

all: build
build:
	docker build --pull -t ${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION} -t ${CONTEXT}/${IMAGE_NAME} -f ${DFILE} .
	@if docker images ${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION}; then touch build; fi

lint:
	dockerfile_lint -f Dockerfile
	dockerfile_lint -f Dockerfile.rhel7

test:
	$(eval TMPDIR=$(shell mktemp -d /tmp/nginx.XXXXX))
	$(eval CONTAINERID=$(shell docker run -tdi -u $(shell id -u) -v ${TMPDIR}:/var/cache/nginx:Z ${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION}))
	@docker exec ${CONTAINERID} curl localhost:8080
	@docker rm -f ${CONTAINERID}
	@rm -r ${TMPDIR}


openshift-test:
	$(eval PROJ_RANDOM=$(shell shuf -i 100000-999999 -n 1))
	oc login -u ${OC_USER} -p ${OC_PASS}
	oc new-project test-${PROJ_RANDOM}
	docker login -u ${OC_USER} -p ${OC_PASS} ${REGISTRY}:5000
	docker tag ${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION} ${REGISTRY}:5000/test-${PROJ_RANDOM}/${IMAGE_NAME}
	docker push ${REGISTRY}:5000/test-${PROJ_RANDOM}/${IMAGE_NAME}
	oc new-app -i ${IMAGE_NAME}
	oc rollout status -w dc/${IMAGE_NAME}
	oc status
	sleep 5
	oc describe pod `oc get pod --template '{{(index .items 0).metadata.name }}'`
	curl `oc get svc/${IMAGE_NAME} --template '{{.spec.clusterIP}}:{{index .spec.ports 0 "port"}}'`

run:
	$(eval TMPDIR=$(shell mktemp -d /tmp/nginx.XXXXX))
	docker run -tdi -u $(shell id -u) -p 8080:8080 -v ${TMPDIR}:/var/cache/nginx:Z ${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION}

clean:
	rm -f build