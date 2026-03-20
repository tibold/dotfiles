#!/bin/bash

# Install packages                        
sudo zypper install -y $(cat packages.txt)

# install.sh                                                        
ln -sf ~/dotfiles/.tmux.conf ~/.tmux.conf
ln -sf ~/dotfiles/.zshrc ~/.zshrc                                   
ln -sf ~/dotfiles/powerline-tmux.conf ~/.config/powerline-tmux.conf

# Clone nvim config                                                 
git clone https://github.com/tibold/astrovim-init.git ~/.config/nvim
                                                                    
