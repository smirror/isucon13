export GO111MODULE=on

SQL_CMD:=mysql -h$(DB_HOST) -P$(DB_PORT) -u$(DB_USER) -p$(DB_PASS) $(DB_NAME)

NGX_LOG:=/var/log/nginx/app.access.log

MYSQL_HOST="127.0.0.1"
MYSQL_PORT=3306
MYSQL_USER=isucon
MYSQL_DBNAME=isupipe
MYSQL_PASS=isucon
MYSQL_LOG:=/var/log/mysql/slow.log

MYSQL=mysql -h$(MYSQL_HOST) -P$(MYSQL_PORT) -u$(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DBNAME)
SLOW_LOG=/var/log/mysql/mysql-slow.log

PPROF:=go tool pprof -png -output pprof.png http://localhost:6060/debug/pprof/profile
PPROF_WEB:=go tool pprof -http=0.0.0.0:1080 webapp/go  http://localhost:6060/debug/pprof/profile

PROJECT_ROOT:=/home/isucon/
BUILD_DIR:=/home/isucon/webapp/go

CA:=-o /dev/null -s -w "%{http_code}\n"

.PHONY:restart-go
restart-go:
	systemctl restart isupipe-go.service

.PHONY: dev
dev: 
	cd $(BUILD_DIR); \
	make \
	sudo systemctl restart isupipe-go.service;

.PHONY: bench-dev
bench-dev: commit before slow-on dev

.PHONY: log
log: 
	sudo journalctl -u isupipe-go -n10 -f

.PHONY: push
push: 
	git push

.PHONY: commit
commit:
	git add .; \
	git commit --allow-empty -m "bench"

.PHONY: before
before:
	$(eval when := $(shell date "+%s"))
	sudo mkdir /var/log/mysql/$(when)
	sudo mkdir /var/log/nginx/$(when)
	@if [ -f $(NGX_LOG) ]; then \
		sudo mv -f $(NGX_LOG) /var/log/nginx/$(when)/ ; \
	fi
	@if [ -f $(MYSQL_LOG) ]; then \
		sudo mv -f $(MYSQL_LOG) /var/log/mysql/$(when)/ ; \
	fi
	sudo systemctl restart nginx mysql

.PHONY: slow
slow:
	sudo pt-query-digest $(MYSQL_LOG) | $(SLACKCAT_MYSQL)

# mysqldumpslowを使ってslow wuery logを出力
# オプションは合計時間ソート
.PHONY: slow-show
slow-show:
	sudo mysqldumpslow -s t $(SLOW_LOG) | head -n 20 | $(SLACKCAT_MYSQL)

# slow-wuery-logを取る設定にする
# DBを再起動すると設定はリセットされる
.PHONY: slow-on
slow-on:
	sudo rm $(SLOW_LOG)
	sudo systemctl restart mysql
	$(MYSQL) -e "set global slow_query_log_file = '$(SLOW_LOG)'; set global long_query_time = 0.001; set global slow_query_log = ON;"

.PHONY: slow-off
slow-off:
	$(MYSQL) -e "set global slow_query_log = OFF;"

# alp

ALPSORT=sum
ALPM="/api/isu/.+/icon,/api/isu/.+/graph,/api/isu/.+/condition,/api/isu/[-a-z0-9]+,/api/condition/[-a-z0-9]+,/api/catalog/.+,/api/condition\?,/isu/........-....-.+"
OUTFORMAT=count,method,uri,min,max,sum,avg,p99

.PHONY: alp-cat
alp-cat:
	sudo alp ltsv --file=/var/log/nginx/access.log --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -m $(ALPM) -q | $(SLACKCAT_ALP)

.PHONY: alpsave
alpsave:
	sudo alp ltsv --file=/var/log/nginx/access.log --pos /tmp/alp.pos --dump /tmp/alp.dump --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -m $(ALPM) -q

.PHONY: alpload
alpload:
	sudo alp ltsv --load /tmp/alp.dump --sort $(ALPSORT) --reverse -o $(OUTFORMAT) -q

.PHONY: pprof
pprof:
	$(PPROF)
	$(SLACKCAT_BENCH) -n pprof.png ./pprof.png

.PHONY: pprof-web
pprof-web:
	go tool pprof -http=0.0.0.0:1080 $(BUILD_DIR)  http://localhost:6060/debug/pprof/profile
