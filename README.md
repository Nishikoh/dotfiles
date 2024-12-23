# dotfiles

[![CI](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml/badge.svg?branch=master)](https://github.com/Nishikoh/dotfiles/actions/workflows/setup.yml)

```sh
git clone https://github.com/Nishikoh/dotfiles.git
cd dotfiles
bash setup.sh
```

or

```sh
curl -sSf https://raw.githubusercontent.com/Nishikoh/dotfiles/refs/heads/master/setup.sh | bash -s -- lazy-setup
```

## develop shell file

```
argc -h
```

## build standalone shell file

```
argc --argc-build Argcfile.sh setup.sh
```

run

```
bash setup.sh
```

## test

```sh
lefthook run lint --all-files
lefthook run test
```
