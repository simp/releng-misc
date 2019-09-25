# If you want to save your container for future use, you use use the `docker
# commit` command
#   * docker commit <running container ID> puppet_agent_build
#   * docker run -it puppet_agent_build
#
# If using buildah, you probably want to build this as follows since various
# things might fail over time:
#   * buildah bud --layers=true -f <filename> .

# Build upstream Ruby
FROM centos:7 as ruby
ENV container docker

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl-devel

RUN curl -O https://cache.ruby-lang.org/pub/ruby/2.5/ruby-2.5.6.tar.gz
RUN tar -xzpvf ruby-2.5.6.tar.gz

WORKDIR /ruby-2.5.6
RUN ./configure && make && make install
RUN /bin/bash -l -c 'gem install bundler'

FROM centos:7 as pl-build-tools
ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl-devel

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

# pl-build-tools-vanagon doesn't tag :'-(
RUN git clone https://github.com/puppetlabs/pl-build-tools-vanagon.git

WORKDIR /pl-build-tools-vanagon
RUN /bin/bash -l -c 'bundle install'
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

FROM centos:7 as puppet-runtime
ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl openssl-devel java which
RUN yum -y install createrepo

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

COPY --from=pl-build-tools /pl-build-tools-vanagon/output /tmp/build-tools

RUN mkdir /tmp/repo
RUN find /tmp/build-tools -name "*.rpm" -exec cp {} /tmp/repo \;
RUN /bin/bash -l -c 'cd /tmp/repo && createrepo .'
RUN echo -e "[pl-local]\nbaseurl=file:///tmp/repo\ngpgcheck=0" > /etc/yum.repos.d/pl-local.repo

RUN git clone https://github.com/puppetlabs/puppet-runtime.git

WORKDIR /puppet-runtime
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
RUN for x in configs/projects/_shared-*; do echo 'proj.setting(:system_openssl, true)' >> $x; done
RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local agent-runtime-master el-7-x86_64'


FROM centos:7 as puppet-agent
ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl openssl-devel which
RUN yum -y install createrepo

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

COPY --from=pl-build-tools /pl-build-tools-vanagon/output /tmp/build-tools

RUN mkdir /tmp/repo
RUN find /tmp/build-tools -name "*.rpm" -exec cp {} /tmp/repo \;
RUN /bin/bash -l -c 'cd /tmp/repo && createrepo .'
RUN echo -e "[pl-local]\nbaseurl=file:///tmp/repo\ngpgcheck=0" > /etc/yum.repos.d/pl-local.repo

RUN yum -y install pl-cmake pl-gcc pl-gettext

COPY --from=puppet-runtime /puppet-runtime/output /tmp/puppet-runtime

RUN git clone https://github.com/puppetlabs/puppet-agent.git

WORKDIR /puppet-agent
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
#RUN sed -i 's/^[[:space:]]*tests[[:space:]]*$/[]/' configs/components/facter.rb

RUN echo "{\"location\":\"file:///tmp/puppet-runtime\",\"version\":\"`ls /tmp/puppet-runtime/agent-runtime-*master*.json | head -1 | sed -e 's/.*master-\(.*\)\.el-7.*/\1/'`\"}" > configs/components/puppet-runtime.json

RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb

RUN /bin/bash -l -c 'gem install rspec mocha'

RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local puppet-agent el-7-x86_64'

CMD /bin/bash
