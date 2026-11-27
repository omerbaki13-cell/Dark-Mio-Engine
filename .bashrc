# Derleme Kısayollaeı
alias ad='echo "Android Derlemesi Başlıyor" && gh workflow run android-arm64.yml'
alias ll='echo "Linux Derlemesi Başlıyor" && haxelib run lime build linux'
alias lw='echo "Windows Derlemesi Başlıyor" && haxelib run lime build windows -mingw -D mingw -D no_shared_libs'
alias li='echo "iOS bulut derlemesi başlatılıyor" && gh workflow run ios-build.yml --repo omerbaki13-cell/Dark-Mio-Engine --ref "$(git branch --show-current)"'
alias ad='echo "Tüm Derlemeler Başlıyor" && drl && li && lw && ll'

# Güncelleme Güncellemeyi Alma
alias gual='git pull origin main'
alias gunc='read -p "Commit mesajı: " msg && git add . && git commit -m "$msg" && git push origin $(git branch --show-current)'

# Güncelleme Güncelleme Alma
alias sm='source ~/Vs-Code/Dark-Mio-Engine/.bashrc'
alias nd='nano ~/Vs-Code/Dark-Mio-Engine/.bashrc'
