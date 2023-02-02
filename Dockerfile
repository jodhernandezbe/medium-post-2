FROM amazonlinux:2.0.20191016.0

RUN yum -y groupinstall "Development Tools"  && \
    yum -y install openssl-devel bzip2-devel libffi-devel

RUN yum -y install wget  && \
    wget https://www.python.org/ftp/python/3.9.10/Python-3.9.10.tgz  && \
    tar xvf Python-3.9.10.tgz

RUN cd Python-3.9.10  && \
    ./configure --enable-optimizations && \
    make altinstall

RUN yum install -y python3-pip && \
    yum install -y zip && \
    yum clean all

RUN python3.9 -m pip install --upgrade pip && \
    python3.9 -m pip install virtualenv