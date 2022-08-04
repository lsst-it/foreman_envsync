# foreman_envsync

A highly opinionated utility to sync foreman puppet environments with the set
of environments known to a `puppetserver` instance *without* also importing the
classes within those puppet environments.

## OCI Image

An OCI image containing this gem is published to docker hub as
[`lsstit/foreman_envsync`](https://hub.docker.com/repository/docker/lsstit/foreman_envsync).


## The Problem

When using [`r10k`](https://github.com/puppetlabs/r10k) with the [Dynamic
Environments](https://github.com/puppetlabs/r10k/blob/main/doc/dynamic-environments.mkd)
pattern in concert with foreman as an ENC, it is highly desirable for new
environments to automatically appear within foreman.  Foreman has a built in
"import environments" feature which triggers a poll of a `puppetserver`'s known
environments.  Foreman's `hammer` CLI has the ability to trigger an import of
all environments (and classes) with the `proxy import-classes` sub-sub-command.
E.g.:

```bash
/bin/hammer proxy import-classes --id=1
```

`r10k` provides a hook to run a shell commands after completing an environment
build, which can be used to invoke `hammer`. E.g.:

```yaml
---
:postrun: ["/bin/hammer", "proxy", "import-classes", "--id=1"]
```

This automation setup is known to work reasonable well on a VM hosting both
`foreman 2.4.0` + `puppetserver 6.15.3` provisioned with 16 x64 cores / 32GiB
RAM / SSD storage under the following conditions:

* The `puppetserver` environment class cache is **enabled**.
* The number of puppet environments is relatively small. I.e. `<= 10`
* [Probably?] The environments are of moderate complexity. I.e. `< ~100` modules
* `r10k` is triggering an import via `hammer` 10s of times per day.

However, it has been observed that all foreman puma workers (regardless of the
number configured) will over time creep up to consume 100% of a core,
interactivity via the www console is abysmal, and environment import may fail
completely when:

* The `puppetserver` environment class cache is **disabled**.
* The puppet environments have `> 100` modules.
* `r10k` is triggering an import via `hammer` 10s of times per day.
* There are `> 10` puppet environments.

Distressingly, when the puppetserver environment cache is **disabled**, even a
small number of puppet agent hosts (~10) will trigger foreman to consume all
available CPU cores.  Reducing the number of puppet environments to `< 10` is
helpful but not a guarantee that an environment/class import will succeed.  It
was observed that above `40` environments, an import is virtually guaranteed to
fail.


##  What Is The Malfunction?

*Disclaimer: This is essentially speculation based on observed behavior and
isn't backed up by careful inspection of the code.*

From external observation of foreman's behavior, it appears that there is a
strong built-in assumption that the `puppetserver` environment class cache is
always enabled and `ETag`s will turn most queries for the classes in an
environment into essentially a no-op.

When a foreman environment import is triggered, foreman not only enumerates
`puppetserver`'s set of known environments via the `/puppet/v3/environments`
API endpoint, it also queries for all the classes within an environment using
`/puppet/v3/environment_classes`.  When the environment class cache is disabled
the time for this query to return seems to be highly variable for the test
environment with response times ranging from a few seconds to over 30s *per
environment*.  This means that an import cycle with many environments can take
10s of minutes.  It appears that something in this process causes foreman's
puma workers to consume 100% of a CPU.  It isn't known if this is busy waiting,
parsing the class list, or something else all together.

Compounding the extremely slow performance caused by bulk environment
importation, foreman also is calling `/puppet/v3/environment_classes` when it
is invoked as an ENC.  This means that every puppet agent run results in a
puppetserver instance compiling an environment to provide a class list to
foreman and then again after ENC/fact data has been supplied to create a
catalog for the agent.

To add insult to injury, in this situation the foreman enc is used solely to
supply parameters and never for class inclusion.  All of the effort to produce
environment class lists and parsing them is completely wasted.


## How Does This Thing Help?

`foreman_envsync` directly obtains the list of puppet environments from
`puppetserver` without requesting class information.  It then removes any
environments which are present in foreman but not within `puppetserver`.  If
there are any unknown-to-foreman environments, then are created as members of
all foreman organizations and locations.  This completely avoids foreman
having to wait on `puppetserver` to provide class lists and parsing them.


## Narrow Use-case

This utility is opinionated and has many hard-coded assumptions. Including:

* It is being installed on Centos 7.
* Foreman and `puppetserver` are installed on the same host.
* Foreman has been installed via `foreman-installer` / puppet code.
* The `puppetserver` TLS related files are in the standard Puppetlabs locations.
* `hammer` CLI has been installed and pre-configure with credentials.
* "new" puppet environments should be visible to all foreman organizations and locations.


## Obvious Improvements

`foreman_envsync` is shelling out to invoke `hammer`. It should probably be
converted to be a `hammer` plugin.

It probably makes sense to use `foreman-proxy` rather than connecting to
`puppetserver` directly as it avoid needing to deal with TLS authentication.

It would be fantastic if foreman's puppet integration was better able to handle
the environment class cache being disabled.  Including:

* Not requesting an environment's class list any time the ENC functionality was invoked.
* A configuration setting to completely disable class handling when it is not needed.
* An option to import environments only (similar to `foreman_envsync`).
* A configuration setting to disable the "import environments" feature which
  also requests class lists.


## Installation

This gem is currently intended to provide `foreman_envsync` CLI utility and not
for use as a library.

It is recommend that it is installed into the foreman `tfm` SCL and that all
dependencies are ignore to avoid disrupting foreman.  It is expected to function
with foremans' gem deps at least as of foreman `2.4.0`.


```bash
scl enable tfm -- gem install --bindir /bin --ignore-dependencies --no-ri --no-rdoc --version 0.1.4 foreman_envsync
```

**If** dependencies need to be installed, the ruby devel package a compiler will be needed. E.g.:

```bash
yum install -y rh-ruby25-ruby-devel devtoolset-7
scl enable devtoolset-7 tfm -- gem install --bindir /bin --ignore-dependencies --no-ri --no-rdoc --version 0.1.4 foreman_envsync
```

### `r10k` Config

It is is highly recommend that the `systemd-cat` utility to be used when configuring the `postrun` hook in `/etc/puppetlabs/r10k/r10k.yaml` so that status output is logged. E.g.:

```yaml
---
:postrun: ["/bin/scl", "enable", "tfm", "--", "systemd-cat", "-t", "foreman_envsync", "/bin/foreman_envsync", "--verbose"]
```

Example of output in the journal when using `systemd-cat`:

```
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: found 13 puppetserver environment(s).
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: ---
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2978_foreman_tuning_ruby
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2953_dds_debugging
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2907_tu_reip
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - production
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - coredev_production
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2978_foreman_tuning
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2373_velero
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2949_poc_encrypt
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2452_pagerduty
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2471_opsgenie
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2879_ipam
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2935_pathfinder_hcu01
Jun 08 23:00:38 foreman.example.org foreman_envsync[10643]: - IT_2987_rpi_puppet
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: found 13 foreman environment(s).
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: ---
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - coredev_production
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2373_velero
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2452_pagerduty
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2471_opsgenie
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2879_ipam
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2907_tu_reip
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2935_pathfinder_hcu01
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2949_poc_encrypt
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2953_dds_debugging
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2978_foreman_tuning
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2978_foreman_tuning_ruby
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - IT_2987_rpi_puppet
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: - production
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: found 0 foreman environment(s) unknown to puppetserver.
Jun 08 23:00:39 foreman.example.org foreman_envsync[10643]: found 0 puppetserver environment(s) unknown to foreman.
```

### `foreman-proxy` Config

If `foreman_envsync` is being considered then it is probably that foreman is also not being used for class inclusion. In that case, there is no reason for foreman to waste wallclock-time waiting for `puppetserver` to return class lists.

The wasted time may be minimized by setting

```yaml
:api_timeout: 1
```

in `/etc/foreman-proxy/settings.d/puppet_proxy_puppet_api.yml` (and restarting
`foreman-proxy`).


## Usage

*Note that `foreman_envsync` requires permissions to read `puppetserver`'s TLS
related files under `/etc/puppetlabs/puppet/ssl`. This may typically be
achieved by membership in the `puppet` group or running as `root`.*

`foreman_envsync` is silent, except for fatal errors, by default:

```bash
scl enable tfm -- foreman_envsync
```

The `--verbose` enables detailed output.

```bash
scl enable tfm -- foreman_envsync --verbose
```

Example of verbose output:

```bash
# scl enable tfm -- foreman_envsync --verbose
found 22 puppetserver environment(s).
---
- master
- IT_2953_dds_debugging
- corecp_production
- IT_2935_pathfinder_hcu01
- coredev_production
- IT_2949_poc_encrypt
- production
- IT_2907_tu_reip
- IT_2373_velero
- IT_2452_pagerduty
- IT_2978_foreman_tuning
- IT_2987_rpi_puppet
- corels_production
- ncsa_production
- disable_IT_2569_tomcat_tls
- tu_production
- disable_IT_2483_letencrypt_renewal
- disable_IT_2417_maddash
- disable_jhoblitt_rspec
- disable_jhoblitt_colina
- IT_2879_ipam
- IT_2471_opsgenie

found 36 foreman environment(s).
---
- corecp_production
- coredev_production
- corels_production
- coretu_production
- IT_2373_velero
- IT_2417_maddash
- IT_2441_dns3_cp
- IT_2452_pagerduty
- IT_2471_opsgenie
- IT_2483_letencrypt_renewal
- IT_2494_nfs
- IT_2569_tomcat_tls
- IT_2613_no_ccs_sal
- IT_2655_net_audit_ls
- IT_2657_dhcp
- IT_2667_poc
- IT_2693_arista
- IT_2694_vlan_change
- IT_2753_comcam_software_v2
- IT_2820_auxtel_ccs
- IT_2854_nfs_export
- IT_2879_ipam
- IT_2907_tu_reip
- IT_2911_ntp
- IT_2935_pathfinder_hcu01
- IT_2949_poc_encrypt
- IT_2953_dds_debugging
- IT_2978_foreman_tuning
- jhoblitt_colina
- jhoblitt_rspec
- master
- ncsa_production
- production
- tickets_DM_25966
- tickets_DM_27839
- tu_production

found 20 foreman environment(s) unknown to puppetserver.
---
- coretu_production
- IT_2417_maddash
- IT_2441_dns3_cp
- IT_2483_letencrypt_renewal
- IT_2494_nfs
- IT_2569_tomcat_tls
- IT_2613_no_ccs_sal
- IT_2655_net_audit_ls
- IT_2657_dhcp
- IT_2667_poc
- IT_2693_arista
- IT_2694_vlan_change
- IT_2753_comcam_software_v2
- IT_2820_auxtel_ccs
- IT_2854_nfs_export
- IT_2911_ntp
- jhoblitt_colina
- jhoblitt_rspec
- tickets_DM_25966
- tickets_DM_27839

deleted 20 foreman environment(s).
---
- message: Environment deleted.
  id: 12
  name: coretu_production
- message: Environment deleted.
  id: 4602
  name: IT_2417_maddash
- message: Environment deleted.
  id: 4664
  name: IT_2441_dns3_cp
- message: Environment deleted.
  id: 4637
  name: IT_2483_letencrypt_renewal
- message: Environment deleted.
  id: 4649
  name: IT_2494_nfs
- message: Environment deleted.
  id: 4658
  name: IT_2569_tomcat_tls
- message: Environment deleted.
  id: 4676
  name: IT_2613_no_ccs_sal
- message: Environment deleted.
  id: 4691
  name: IT_2655_net_audit_ls
- message: Environment deleted.
  id: 4688
  name: IT_2657_dhcp
- message: Environment deleted.
  id: 4736
  name: IT_2667_poc
- message: Environment deleted.
  id: 4709
  name: IT_2693_arista
- message: Environment deleted.
  id: 4710
  name: IT_2694_vlan_change
- message: Environment deleted.
  id: 4771
  name: IT_2753_comcam_software_v2
- message: Environment deleted.
  id: 4746
  name: IT_2820_auxtel_ccs
- message: Environment deleted.
  id: 4792
  name: IT_2854_nfs_export
- message: Environment deleted.
  id: 4762
  name: IT_2911_ntp
- message: Environment deleted.
  id: 4735
  name: jhoblitt_colina
- message: Environment deleted.
  id: 4619
  name: jhoblitt_rspec
- message: Environment deleted.
  id: 4581
  name: tickets_DM_25966
- message: Environment deleted.
  id: 4686
  name: tickets_DM_27839

found 6 puppetserver environment(s) unknown to foreman.
---
- IT_2987_rpi_puppet
- disable_IT_2569_tomcat_tls
- disable_IT_2483_letencrypt_renewal
- disable_IT_2417_maddash
- disable_jhoblitt_rspec
- disable_jhoblitt_colina

found 1 foreman location(s).
---
- 2

found 1 foreman organization(s).
---
- 1

created 6 foreman environment(s).
---
- message: Environment created.
  id: 4800
  name: IT_2987_rpi_puppet
- message: Environment created.
  id: 4801
  name: disable_IT_2569_tomcat_tls
- message: Environment created.
  id: 4802
  name: disable_IT_2483_letencrypt_renewal
- message: Environment created.
  id: 4803
  name: disable_IT_2417_maddash
- message: Environment created.
  id: 4804
  name: disable_jhoblitt_rspec
- message: Environment created.
  id: 4805
  name: disable_jhoblitt_colina
```


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lsst-it/foreman_envsync.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
