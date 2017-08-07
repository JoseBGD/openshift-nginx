CONTEXT = nginxinc
VERSION = 1.13.3
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
	$(eval ARB_UID=$(shell shuf -i 1000010000-1000020000 -n 1))
	$(eval VOL_LIST=$(shell docker inspect -f '{{range $$p, $$vol := .Config.Volumes}} {{json $$p}} {{end}}' ${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION}))
	$(eval TMPFS=$(shell for i in ${VOL_LIST}; do VOLS="$${VOLS} --tmpfs $${i}:mode=2777,gid=${ARB_UID}"; done; echo $${VOLS}))
	$(eval CONTAINERID=$(shell docker run -tdi -u ${ARB_UID} --group-add ${ARB_UID} \
	${TMPFS} \
	--cap-drop=KILL \
	--cap-drop=MKNOD \
	--cap-drop=SYS_CHROOT \
	--cap-drop=SETUID \
	--cap-drop=SETGID \
	${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION}))
	@sleep 3
	@echo "View processes..."
	docker exec ${CONTAINERID} ps aux
	@echo ""
	@echo "Check id information..."
	docker exec ${CONTAINERID} id
	@echo ""
	@echo "Check volume(s)..."
	@for i in ${VOL_LIST}; do docker exec ${CONTAINERID} mountpoint $${i}; docker exec ${CONTAINERID} mount | grep -w $${i} | grep tmpfs; done
	@docker exec ${CONTAINERID} curl localhost:8080
	@docker rm -vf ${CONTAINERID}

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
	$(eval ARB_UID=$(shell shuf -i 1000010000-1000020000 -n 1))
	$(eval VOL_LIST=$(shell docker inspect -f '{{range $$p, $$vol := .Config.Volumes}} {{json $$p}} {{end}}' ${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION}))
	$(eval TMPFS=$(shell for i in ${VOL_LIST}; do VOLS="$${VOLS} --tmpfs $${i}:mode=2777,gid=${ARB_UID}"; done; echo $${VOLS}))
	docker run -tdi -u ${ARB_UID} --group-add ${ARB_UID} \
	${TMPFS} \
	-p 8080:8080 \
	--cap-drop=KILL \
	--cap-drop=MKNOD \
	--cap-drop=SYS_CHROOT \
	--cap-drop=SETUID \
	--cap-drop=SETGID \
	${CONTEXT}/${IMAGE_NAME}:${TARGET}-${VERSION}

clean:
	rm -f build
