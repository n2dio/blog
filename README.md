# n2d.io static site blog

## Development
### Prerequesites
For local development, you need `zola` to be installed. This can be done via your favorite package manager or manually. For details, see the [installation instructions][0]

[0]: https://www.getzola.org/documentation/getting-started/installation/

After cloning the repository initially, please ensure to also initializa the theme submodule by running

```bash
git pull --recurse-submodules
```

### Serving and building locally
For running the site locally, which rebuilds on every file change, just run:

```bash
zola serve
```

For building the whole site (to the `public` folder), just run:

```bash
zola build
```

## Deployment
### Provisioning
Provisioning is not fully automated, yet. For more details, see the [provisioning][1] repository.

### Continuous Deployment
The continuous deployment works via Github Actions and pushes the statically generated content to n2d.io. For more details, just see the [n2d workflow definition][2].


## Credits
This blog uses awesome software, written by others: 
- [zola][3] as static site generator and
- [even][4] as a theme.

[1]: https://github.com/n2dio/provision
[2]: https://github.com/n2dio/blog/blob/main/.github/workflows/main.yml
[3]: https://www.getzola.org/
[4]: https://www.getzola.org/themes/even/
