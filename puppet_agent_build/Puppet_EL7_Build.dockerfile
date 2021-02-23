# If you want to save your container for future use, you use use the `docker
# commit` command
#   * docker commit <running container ID> puppet_agent_build
#   * docker run -it puppet_agent_build
#
# If using buildah, you probably want to build this as follows since various
# things might fail over time:
#   * buildah bud --layers=true -f <filename> .
#
# You can choose to build a specific version of puppet by setting the
# PUPPET_VERSION environment variable to a valid git reference in the
# puppet-agent repository.
#
# By default, the latest tag will be built.

# A common base image

FROM centos:7 as base
ENV container docker

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl openssl-devel java which
RUN yum -y install createrepo

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

RUN mkdir /tmp/repo

# Build upstream Ruby
FROM base as ruby
ENV container docker

RUN curl -O https://cache.ruby-lang.org/pub/ruby/2.5/ruby-2.5.6.tar.gz
RUN tar -xzpvf ruby-2.5.6.tar.gz

WORKDIR /ruby-2.5.6
RUN ./configure --disable-install-doc && make && make install
RUN /bin/bash -l -c 'gem install bundler'

FROM base as pl-build-tools
ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

# pl-build-tools-vanagon doesn't tag :'-(
RUN git clone https://github.com/puppetlabs/pl-build-tools-vanagon.git

WORKDIR /pl-build-tools-vanagon
RUN /bin/bash -l -c 'bundle install'
RUN sed -i '/proj\.component.\+openssl-.*/d' configs/platforms/*.rb
RUN sed -i '0,/^\([[:space:]]*\)\+proj\.component/s//\1proj.setting(:system_openssl, true)\n&/' configs/projects/*.rb
RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pl-gcc el-7-x86_64'
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pl-cmake el-7-x86_64'
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pl-gettext el-7-x86_64'
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pl-ruby el-7-x86_64'
RUN find output -name *.rpm | xargs yum -y install
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pl-openssl el-7-x86_64'
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pl-boost el-7-x86_64'
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pl-yaml-cpp el-7-x86_64'
RUN find output -name *.rpm | xargs yum -y install
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pl-curl el-7-x86_64'

FROM base as build_tools_base
ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

COPY --from=pl-build-tools /pl-build-tools-vanagon/output /tmp/build-tools

RUN find /tmp/build-tools -name "*.rpm" -exec cp {} /tmp/repo \;
RUN /bin/bash -l -c 'cd /tmp/repo && createrepo .'
RUN echo -e "[pl-local]\nbaseurl=file:///tmp/repo\ngpgcheck=0" > /etc/yum.repos.d/pl-local.repo

RUN yum -y install pl-cmake pl-gcc pl-gettext

FROM build_tools_base as puppet-runtime
ENV container docker

RUN git clone https://github.com/puppetlabs/puppet-runtime.git

WORKDIR /puppet-runtime
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
RUN sed -i '0,/^\([[:space:]]*\)\+proj\.component/s//\1proj.setting(:system_openssl, true)\n&/' configs/projects/*.rb

RUN sed -i '/proj\.component.\+openssl-.*/d' configs/{projects,platforms}/*.rb
RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local agent-runtime-main el-7-x86_64'
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local bolt-runtime el-7-x86_64'

FROM build_tools_base as runtime_base
ENV container docker

COPY --from=puppet-runtime /puppet-runtime/output /tmp/puppet-runtime

FROM runtime_base as pxp-agent
ARG PXP_AGENT_VERSION=latest
ENV pxp_agent_version $PXP_AGENT_VERSION

ENV container docker

RUN git clone https://github.com/puppetlabs/pxp-agent-vanagon.git

WORKDIR /pxp-agent-vanagon
RUN sed -i 's|gem.*vanagon.*|gem "vanagon"|' Gemfile
RUN if [ "${pxp_agent_version}" == 'latest' ]; then git checkout $(git describe --tags $(git rev-list --tags --max-count=1)); else git checkout "${pxp_agent_version}"; fi
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
#RUN sed -i 's/^[[:space:]]*tests[[:space:]]*$/[]/' configs/components/facter.rb

RUN echo "{\"location\":\"file:///tmp/puppet-runtime\",\"version\":\"`ls /tmp/puppet-runtime/agent-runtime-*main*.json | head -1 | sed -e 's/.*main-\(.*\)\.el-7.*/\1/'`\"}" > configs/components/puppet-runtime.json

RUN sed -i '/proj\.component.\+openssl-.*/d' configs/platforms/*.rb
RUN sed -i '0,/^\([[:space:]]*\)\+proj\.component/s//\1proj.setting(:system_openssl, true)\n&/' configs/projects/*.rb
RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb

RUN /bin/bash -l -c 'gem install rspec mocha'

RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pxp-agent el-7-x86_64'

CMD /bin/bash

FROM runtime_base as puppet-agent
ARG PUPPET_VERSION=latest
ENV puppet_version $PUPPET_VERSION

ENV container docker

COPY --from=pxp-agent /pxp-agent-vanagon/output /tmp/pxp-agent

RUN git clone https://github.com/puppetlabs/puppet-agent.git

WORKDIR /puppet-agent
RUN if [ "${puppet_version}" == 'latest' ]; then git checkout $(git describe --tags $(git rev-list --tags --max-count=1)); else git checkout "${puppet_version}"; fi
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
#RUN sed -i 's/^[[:space:]]*tests[[:space:]]*$/[]/' configs/components/facter.rb

RUN echo "{\"location\":\"file:///tmp/puppet-runtime\",\"version\":\"`ls /tmp/puppet-runtime/agent-runtime-*main*.json | head -1 | sed -e 's/.*main-\(.*\)\.el-7.*/\1/'`\"}" > configs/components/puppet-runtime.json
RUN echo "{\"location\":\"file:///tmp/pxp-agent\",\"version\":\"`ls /tmp/pxp-agent/pxp-agent-*.json | head -1 | sed -e 's/.*-\([[:digit:]]\+\)\.el-7.*/\1/'`\"}" > configs/components/pxp-agent.json

RUN sed -i '/proj\.component.\+openssl-.*/d' configs/platforms/*.rb
RUN sed -i '0,/^\([[:space:]]*\)\+proj\.component/s//\1proj.setting(:system_openssl, true)\n&/' configs/projects/*.rb
RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb

RUN /bin/bash -l -c 'gem install rspec mocha'

RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local puppet-agent el-7-x86_64'

CMD /bin/bash

FROM runtime_base as bolt
ENV container docker

RUN git clone https://github.com/puppetlabs/bolt-vanagon.git

WORKDIR /bolt-vanagon
RUN if [ "${PUPPET_VERSION}" == 'latest' ]; then git checkout $(git describe --tags $(git rev-list --tags --max-count=1)); else git checkout "${PUPPET_VERSION}"; fi
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
#RUN sed -i 's/^[[:space:]]*tests[[:space:]]*$/[]/' configs/components/facter.rb

RUN echo "{\"location\":\"file:///tmp/puppet-runtime\",\"version\":\"`ls /tmp/puppet-runtime/agent-runtime-*main*.json | head -1 | sed -e 's/.*main-\(.*\)\.el-7.*/\1/'`\"}" > configs/components/puppet-runtime.json
RUN echo "{\"location\":\"file:///tmp/bolt-runtime\",\"version\":\"`ls /tmp/puppet-runtime/bolt-runtime-*.json | head -1 | sed -e 's/.*-\([[:digit:]]\+\)\.el-7.*/\1/'`\"}" > configs/components/pxp-agent.json

RUN sed -i '/proj\.component.\+openssl-.*/d' configs/platforms/*.rb
RUN sed -i '0,/^\([[:space:]]*\)\+proj\.component/s//\1proj.setting(:system_openssl, true)\n&/' configs/projects/*.rb
RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb

RUN /bin/bash -l -c 'gem install rspec mocha'

# Fixed in https://github.com/puppetlabs/bolt-vanagon/commit/bdc14d79837b18a3e8960e888258a1f3ad9a662c
RUN sed -i 's/metadata_uri =.*/metadata_uri = File.join(runtime_details["location"], %(bolt-runtime-#{runtime_details["version"]}.#{platform.name}.json))/' configs/projects/puppet-bolt.rb

RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local puppet-bolt el-7-x86_64'

CMD /bin/bash
