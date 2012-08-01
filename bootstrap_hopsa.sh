#!/bin/sh

need_install=0
git --version &>/dev/null
if [ "$?" != 0 ]; then
  need_install=1
fi
curl --version &>/dev/null
if [ "$?" != 0 ]; then
  need_install=1
fi
if [ ! -f /usr/include/zlib.h ]; then
  need_install=1
fi
if [ "$need_install" = 1 ]; then
  if apt-get --version &>/dev/null; then
    sudo apt-get -y install git-core curl zlib1g zlib1g-dev openssl libssl-dev
  elif yum --version &>/dev/null; then
    sudo yum -y install git-core curl zlib zlib-devel openssl-devel openssl
  fi
fi

curl https://raw.github.com/fesplugas/rbenv-installer/master/bin/rbenv-installer | bash
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
echo 'eval "$(rbenv init -)"' >> ~/.bash_profile

export RBENV_ROOT="${HOME}/.rbenv"
export PATH="${RBENV_ROOT}/bin:${PATH}"
eval "$(rbenv init -)"

rbenv install 1.9.3-p194
rbenv global 1.9.3-p194
gem install bundler
rbenv rehash

git clone http://github.com/zhum/hoplang
bundle install

