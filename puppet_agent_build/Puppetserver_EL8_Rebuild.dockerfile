#  This docker file will will download and rebuild the latest
#  puppet 6 puppetserver package for EL8 so the package is signed
#  correctly for installing on a FIPS system.
#
#  To run and  copy the file:
#  * docker build -f ./Puppetserver_EL8_Rebuild.dockerfile -t psrv_rpm .
#  * docker run --name=prpm psrv_rpm
#  * docker cp prpm:/root/<where it tells you the file is> <where you want the file>
#
#  Then remove the container and images
#   * docker container rm prpm
#   * docker rmi psrv_rpm
#
# Build upstream Ruby
FROM centos:8
ENV container docker

WORKDIR /root

RUN yum -y install rpm-build yum-utils java-headless net-tools

# There's no rpmrebuild in EPEL yet
RUN rpm -i --nodigest --nofiledigest https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/r/rpmrebuild-2.11-3.el7.noarch.rpm

RUN yum -y install https://yum.puppet.com/puppet6-release-el-8.noarch.rpm
RUN yum -y install puppet-agent
RUN yumdownloader puppetserver

RUN rpm -i --nodigest --nofiledigest puppetserver*.rpm

RUN dist=`rpm --eval '%{dist}'`; release=`rpm -q --qf="%{release}" puppetserver | cut -f1 -d'.'`; rpmrebuild --batch --release="${release}.SIMP1${dist}" puppetserver

RUN echo '############'; echo -n "Your file is at:"; find rpmbuild/RPMS -name "*.rpm"; echo '##########'

CMD /bin/bash
