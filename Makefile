export GO111MODULE=on

all: bin/benchmarker bin/benchmark-worker bin/payment bin/shipment

bin/benchmarker: cmd/bench/main.go bench/**/*.go
	go build -o bin/benchmarker cmd/bench/main.go

bin/benchmark-worker: cmd/bench-worker/main.go
	go build -o bin/benchmark-worker cmd/bench-worker/main.go

bin/payment: cmd/payment/main.go bench/server/*.go
	go build -o bin/payment cmd/payment/main.go

bin/shipment: cmd/shipment/main.go bench/server/*.go
	go build -o bin/shipment cmd/shipment/main.go

vet:
	go vet ./...

errcheck:
	errcheck ./...

staticcheck:
	staticcheck -checks="all,-ST1000" ./...

include ~/env.sh

DB_HOST:=172.31.36.37
DB_PORT:=3306
DB_USER:=isucari
DB_PASS:=isucari
DB_NAME:=isucari

GOPATH:=/home/isucon/go/bin

MYSQL_CMD:=mysql -h$(DB_HOST) -P$(DB_PORT) -u$(DB_USER) -p$(DB_PASS) $(DB_NAME)

NGINX_LOG:=/var/log/nginx/access.log
MYSQL_LOG:=/var/log/mysql/mysql-slow.log
MYSQL_PATH := /var/log/mysql
KATARU_CFG:=./kataribe.toml

SLACKCAT:=slackcat --tee --channel general
SLACKRAW:=slackcat --channel general

PPROF:=go tool pprof -png -output pprof.png http://localhost:6060/debug/pprof/profile

PROJECT_ROOT:=/home/isucon/isucari
BUILD_DIR:=/home/isucon/isucari/webapp/go
BIN_NAME:=isucari
BIN_DIR:=/home/isucon/isucari

SERVICE_NAME:=isucari.golang.service

DB_PATH:=/etc/mysql
NGINX_PATH:=/etc/nginx
SYSTEMD_PATH:=/etc/systemd/system

CA:=-o /dev/null -s -w "%{http_code}\n"

B:="hoge"

.PHONY: clean
clean:
	rm -rf bin/*
	cd $(BUILD_DIR); \
	rm -rf $(BIN_NAME)

deps:
	cd $(BUILD_DIR); \
	go mod download

.PHONY: build
build:
	cd $(BUILD_DIR); \
	go build -o $(BIN_NAME)

.PHONY: restart
restart:
	sudo systemctl restart $(SERVICE_NAME)

.PHONY: test
test:
	curl localhost $(CA)

# ここから元から作ってるやつ

# 設定ファイルなどを取得してgit管理下に配置する
.PHONY: get-conf
get-conf: check-server-id dir get-db-conf get-envsh get-nginx-conf get-service-file

# リポジトリ内の設定ファイルをそれぞれ配置する
.PHONY: deploy-conf
deploy-conf: check-server-id deploy-db-conf deploy-envsh deploy-nginx-conf deploy-service-file

.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

.PHONY: set-as-s1
set-as-s1:
	echo "SERVER_ID=s1" >> ~/env.sh

.PHONY: set-as-s2
set-as-s2:
	echo "SERVER_ID=s2" >> ~/env.sh

.PHONY: set-as-s3
set-as-s3:
	echo "SERVER_ID=s3" >> ~/env.sh

.PHONY: dir
dir:
	mkdir $(BIN_DIR)/$(SERVER_ID)
	mkdir $(BIN_DIR)/$(SERVER_ID)/etc
	mkdir $(BIN_DIR)/$(SERVER_ID)/etc/mysql
	mkdir $(BIN_DIR)/$(SERVER_ID)/etc/nginx
	mkdir $(BIN_DIR)/$(SERVER_ID)/etc/systemd
	mkdir $(BIN_DIR)/$(SERVER_ID)/etc/systemd/system
	mkdir $(BIN_DIR)/$(SERVER_ID)/home
	mkdir $(BIN_DIR)/$(SERVER_ID)/home/isucon

.PHONY: get-db-conf
get-db-conf:
	sudo cp -R $(DB_PATH)/* $(BIN_DIR)/$(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R $(BIN_DIR)/$(SERVER_ID)/etc/mysql

.PHONY: get-nginx-conf
get-nginx-conf:
	sudo cp -R $(NGINX_PATH)/* $(BIN_DIR)/$(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R $(BIN_DIR)/$(SERVER_ID)/etc/nginx

.PHONY: get-service-file
get-service-file:
	sudo cp $(SYSTEMD_PATH)/$(SERVICE_NAME) $(BIN_DIR)/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)
	sudo chown $(USER) $(BIN_DIR)/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME)

.PHONY: get-envsh
get-envsh:
	cp ~/env.sh $(BIN_DIR)/$(SERVER_ID)/home/isucon/env.sh

.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -R $(BIN_DIR)/$(SERVER_ID)/etc/mysql/* $(DB_PATH)

.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -R $(BIN_DIR)/$(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

.PHONY: deploy-service-file
deploy-service-file:
	sudo cp $(BIN_DIR)/$(SERVER_ID)/etc/systemd/system/$(SERVICE_NAME) $(SYSTEMD_PATH)/$(SERVICE_NAME)

.PHONY: deploy-envsh
deploy-envsh:
	cp $(BIN_DIR)/$(SERVER_ID)/home/isucon/env.sh ~/env.sh


.PHONY: dev
dev: build
	cd $(BUILD_DIR); \
	sudo systemctl restart $(SERVICE_NAME)

.phony: pull
pull:
	git fetch
	git pull

.PHONY: bench
bench: check-server-id pull deploy-conf before build restart

.PHONY: maji
maji: before build restart

.PHONY: co
co:
	git fetch
	git checkout -b $(B) origin/$(B)

.PHONY: commit
commit:
	cd $(PROJECT_ROOT); \
	git add .; \
	@read -p "変更点は: " message; \
	git commit --allow-empty -m $$message

.PHONY: rm
rm:
	rm docker-compose.yml

.PHONY: before
before:
	sudo chmod 777 $(MYSQL_PATH)
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/$(when)
	@if [ -f $(NGINX_LOG) ]; then \
		sudo mv -f $(NGINX_LOG) ~/logs/$(when)/ ; \
	fi
	sudo systemctl daemon-reload
	sudo systemctl restart nginx
	sudo systemctl restart mysql

.PHONY: slow
slow:
	sudo mysqldumpslow -s t $(MYSQL_LOG) | $(SLACKCAT)

.PHONY: slow-less
slow-less:
	sudo mysqldumpslow -s t $(MYSQL_LOG) | less

.PHONY: slow-pt
slow-pt:
	sudo cat $(MYSQL_LOG) | pt-query-digest | $(SLACKCAT)

.PHONY: kataru
kataru:
	sudo cat $(NGINX_LOG) | $(GOPATH)/kataribe -f ./kataribe.toml | cat

.PHONY: pprof
pprof:
	$(PPROF)
	$(SLACKRAW) -n pprof.png ./pprof.png

.PHONY: slow-on
slow-on:
	$(MYSQL_CMD) -e "set global slow_query_log_file = '$(MYSQL_LOG)'; set global long_query_time = 0; set global slow_query_log = ON;"

.PHONY: slow-off
slow-off:
	$(MYSQL_CMD) -e "set global slow_query_log = OFF;"

.PHONY: status
status:
	sudo systemctl status $(SERVICE_NAME)

.PHONY: db
db:
	$(MYSQL_CMD)

.PHONY: git-setup
git-setup:
	git init
	git config --global user.email "you@example.com"
	git config --global user.name "isucon-server"
	ssh-keygen -t ed25519

.PHONY: setup
setup:
	sudo add-apt-repository ppa:longsleep/golang-backports
	sudo apt update
	sudo apt upgrade -y
	mkdir ~/bin -p
	sudo apt install -y percona-toolkit dstat git unzip snapd graphviz tree golang-go
	go get github.com/matsuu/kataribe@latest
	$(GOPATH)/kataribe -generate
	curl -Lo slackcat https://github.com/bcicen/slackcat/releases/download/1.7.2/slackcat-1.7.2-$$(uname -s)-amd64
	sudo mv slackcat /usr/local/bin/
	sudo chmod +x /usr/local/bin/slackcat
	slackcat --configure
