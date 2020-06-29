ARG RUBY=2.6
ARG ALPINE=3.11
FROM ruby:${RUBY}-alpine${ALPINE}
LABEL maintainer="Instructure"

ARG ALPINE_MIRROR
ENV ALPINE_MIRROR ${ALPINE_MIRROR:-http://dl-cdn.alpinelinux.org/alpine/}

ARG PASSENGER=6.0.5
# at the time of authoring this, master was 2f444c6 for these files
ARG PASSENGER_APT_AUTOMATION_SHA=2f444c6

ENV NGINX_PATH=/opt/nginx
ENV SRC_PATH=/usr/src
ENV PASSENGER_PATH=/opt/passenger
ENV PATH=${PASSENGER_PATH}/bin:${NGIN_PATH}/sbin:$PATH
ENV PASSENGER_NGINX_APT_SRC_PATH=${SRC_PATH}/passenger-nginx-apt-src
ENV NGINX_MODULES_PATH=${PASSENGER_NGINX_APT_SRC_PATH}/modules

# this file is cribbed from
# https://github.com/phusion/passenger_apt_automation/debian_specs/nginx/rules
COPY rules ${PASSENGER_NGINX_APT_SRC_PATH}/

RUN set -eux; \
  \
  # create "docker" user \
  addgroup -g 9999 docker \
  && adduser -D -u 9999 -g "Docker User" docker -G docker \
  \
  # these packages remain \
  && apk add --no-cache --virtual .systemRuntimeDeps \
    sudo \
  # these packages remain \
  && apk add --no-cache --virtual .nginxRuntimeDeps \
    ca-certificates \
    curl \
    libnsl \
    openssl \
    linux-pam \
    lua5.1 \
    perl \
    gd \
    geoip \
  # these packages will be removed \
  && apk add --no-cache --virtual .nginxBuildDeps \
    expat-dev \
    gd-dev \
    geoip-dev \
    libxml2-dev \
    libxslt-dev \
    linux-pam-dev \
    lua5.1-dev \
    perl-dev \
  # these packages will be removed \
  && apk add --no-cache --virtual .buildDeps \
    curl-dev \
    g++ \
    make \
    openssl-dev \
    wget \
    zlib \
  # quilt only exists in this other repo. it will be removed later in the build \
  && apk add --no-cache --virtual .quilt --repository http://mirrors.gigenet.com/alpinelinux/edge/testing quilt \
  && curl -sL http://s3.amazonaws.com/phusion-passenger/releases/passenger-${PASSENGER}.tar.gz | tar -zxC /opt/ \
  && mv ${PASSENGER_PATH}-${PASSENGER} ${PASSENGER_PATH} \
  && echo "PATH=${PASSENGER_PATH}/bin:$PATH" >> /etc/bashrc \
  # workaround for this error which seems to be a bug that has been fixed in newer versions: \
  #     sudo: setrlimit(RLIMIT_CORE): Operation not permitted \
  # ref: https://github.com/sudo-project/sudo/issues/42 \
  && echo "Set disable_coredump false" >> /etc/sudo.conf \
  && echo "docker ALL=(ALL) NOPASSWD: SETENV: ${NGINX_PATH}/sbin/nginx" >> /etc/sudoers \
  && passenger-config compile-agent --optimize --auto \
  # fetch the official repo for building the apt packages so we can reuse the existing modules and patches \
  && curl -sL https://github.com/phusion/passenger_apt_automation/tarball/${PASSENGER_APT_AUTOMATION_SHA} | tar -zxC ${SRC_PATH} \
  && mv ${SRC_PATH}/phusion-passenger_apt_automation-${PASSENGER_APT_AUTOMATION_SHA}/debian_specs/nginx/modules ${PASSENGER_NGINX_APT_SRC_PATH} \
  && rm -rf ${SRC_PATH}/phusion-passenger_apt_automation-${PASSENGER_APT_AUTOMATION_SHA} \
  && cd ${PASSENGER_NGINX_APT_SRC_PATH} \
  && make -f rules config_patch_modules \
  && gem install rack \
  # sourced from: https://github.com/phusion/passenger_apt_automation/blob/master/debian_specs/nginx/rules \
  && extraConfigureFlags=" \
    --add-module=${NGINX_MODULES_PATH}/headers-more-nginx-module \
    --add-module=${NGINX_MODULES_PATH}/nchan \
    --add-module=${NGINX_MODULES_PATH}/nginx-auth-pam \
    --add-module=${NGINX_MODULES_PATH}/nginx-cache-purge \
    --add-module=${NGINX_MODULES_PATH}/nginx-dav-ext-module \
    --add-module=${NGINX_MODULES_PATH}/nginx-development-kit \
    --add-module=${NGINX_MODULES_PATH}/nginx-echo \
    --add-module=${NGINX_MODULES_PATH}/nginx-lua \
    --add-module=${NGINX_MODULES_PATH}/nginx-upload-progress \
    --add-module=${NGINX_MODULES_PATH}/nginx-upstream-fair \
    --add-module=${NGINX_MODULES_PATH}/ngx-fancyindex \
    --add-module=${NGINX_MODULES_PATH}/ngx_http_substitutions_filter_module \
    --with-compat \
    --with-debug \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_geoip_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_image_filter_module \
    --with-http_mp4_module \
    --with-http_perl_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_xslt_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-pcre-jit \
    --with-stream \
    --with-stream_ssl_module \
    --with-threads \
  " \
  && passenger-install-nginx-module --auto --auto-download --prefix=${NGINX_PATH} --extra-configure-flags="$extraConfigureFlags" \
  && gem uninstall rack \
  && cd - \
  && apk del --no-network .quilt .nginxBuildDeps .buildDeps \
  # ref: https://github.com/instructure/dockerfiles/blob/master/ruby-passenger/2.6/Dockerfile \
  && mkdir -p ${SRC_PATH}/nginx/conf.d \
  && mkdir -p ${SRC_PATH}/nginx/location.d \
  && mkdir -p ${SRC_PATH}/nginx/main.d \
  && mkdir -p /var/log/nginx \
  && ln -sf /usr/lib/libnsl.so.2 /usr/lib/libnsl.so.1 \
  && ln -sf /dev/stdout /var/log/nginx/access.log \
  && ln -sf /dev/stderr /var/log/nginx/error.log \
  && chown docker:docker -R ${SRC_PATH}/nginx \
  && rm -rf $PASSENGER_NGINX_APT_SRC_PATH \
  && rm -rf /tmp/*

COPY entrypoint ${SRC_PATH}/entrypoint
COPY main.d/* ${SRC_PATH}/nginx/main.d/
COPY nginx.conf.erb ${SRC_PATH}/nginx/nginx.conf.erb

USER docker

EXPOSE 80

CMD ["/usr/src/entrypoint"]
