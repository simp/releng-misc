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

# Build upstream Ruby
FROM centos:8 AS ruby
ENV container docker

ARG PUPPET_VERSION=latest
ENV puppet_version=$PUPPET_VERSION

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl-devel

RUN curl -O https://cache.ruby-lang.org/pub/ruby/2.5/ruby-2.5.7.tar.gz
RUN tar -xzpvf ruby-2.5.7.tar.gz

WORKDIR /ruby-2.5.7
RUN ./configure && make && make install
RUN /bin/bash -l -c 'gem install bundler'

FROM centos:8 As pl-build-tools
ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl-devel which

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

RUN mkdir /tmp/repo

RUN git clone https://github.com/puppetlabs/puppet-runtime.git

WORKDIR /puppet-runtime
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
RUN for x in configs/projects/_shared-*; do echo 'proj.setting(:system_openssl, true)' >> $x; done
RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local agent-runtime-master el-8-x86_64'

FROM centos:8 AS puppet-agent
ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl openssl-devel which
RUN yum -y install createrepo

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

COPY --from=pl-build-tools /puppet-runtime/output /tmp/puppet-runtime

RUN git clone https://github.com/puppetlabs/puppet-agent.git

WORKDIR /puppet-agent
RUN if [ "${PUPPET_VERSION}" == 'latest' ]; then git checkout $(git describe --tags $(git rev-list --tags --max-count=1)); else git checkout "${PUPPET_VERSION}"; fi
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
#RUN sed -i 's/^[[:space:]]*tests[[:space:]]*$/[]/' configs/components/facter.rb

RUN echo "{\"location\":\"file:///tmp/puppet-runtime\",\"version\":\"`ls /tmp/puppet-runtime/agent-runtime-*master*.json | head -1 | sed -e 's/.*master-\(.*\)\.el-8.*/\1/'`\"}" > configs/components/puppet-runtime.json

RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb

# Hack for fixing facter-ng thor dependency
RUN sed -i 's/settings\[:gem_install\]/settings[:gem_install].gsub("--local","")/' configs/components/facter-ng.rb

RUN /bin/bash -l -c 'gem install rspec mocha'

RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local puppet-agent el-8-x86_64'

CMD /bin/bash
