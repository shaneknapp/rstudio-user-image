FROM rocker/rstudio:4.5.1
# https://github.com/rocker-org/rocker-versioned2/wiki/geospatial_871e1512223f

ENV NB_USER=rstudio
ENV NB_UID=1000
ENV CONDA_DIR=/srv/conda
ENV R_LIBS_USER=/srv/r
ENV DEFAULT_PATH=${PATH}

# Set ENV for all programs...
ENV PATH=${CONDA_DIR}/bin:$PATH

ENV TZ=ENV TZ=America/Los_Angeles

# And set ENV for R! It doesn't read from the environment...
RUN echo "TZ=${TZ}" >> /usr/local/lib/R/etc/Renviron.site
RUN echo "PATH=${PATH}" >> /usr/local/lib/R/etc/Renviron.site

# Add PATH to /etc/profile so it gets picked up by the terminal
RUN echo "PATH=${PATH}" >> /etc/profile
RUN echo "export PATH" >> /etc/profile

ENV HOME=/home/${NB_USER}

WORKDIR ${HOME}

# Install all apt packages
COPY apt.txt /tmp/apt.txt
RUN apt-get -qq update --yes && \
    apt-get -qq install --yes --no-install-recommends \
        $(grep -v ^# /tmp/apt.txt) && \
    apt-get -qq purge && \
    apt-get -qq clean && \
    rm -rf /var/lib/apt/lists/*

ENV SHINY_SERVER_URL=https://download3.rstudio.org/ubuntu-20.04/x86_64/shiny-server-1.5.23.1030-amd64.deb
RUN curl --silent --location --fail ${SHINY_SERVER_URL} > /tmp/shiny-server.deb && \
    apt install --no-install-recommends --yes /tmp/shiny-server.deb && \
    rm /tmp/shiny-server.deb

# Install our custom Rprofile.site file
COPY Rprofile.site /usr/lib/R/etc/Rprofile.site
# Create directory for additional R/RStudio setup code
RUN mkdir /etc/R/Rprofile.site.d
# RStudio needs its own config
COPY rsession.conf /etc/rstudio/rsession.conf
# set up basic rstudio user config
COPY rstudio-prefs.json /etc/rstudio/rstudio-prefs.json

RUN install -d -o ${NB_USER} -g ${NB_USER} ${CONDA_DIR}

# Install conda environment as our user
USER ${NB_USER}
COPY --chown=1000:1000 install-miniforge.bash /tmp/install-miniforge.bash
RUN /tmp/install-miniforge.bash
RUN rm -f /tmp/install-miniforge.bash

USER ${NB_USER}
COPY --chown=1000:1000 environment.yml /tmp/environment.yml
ENV PATH=${CONDA_DIR}/bin:$PATH
RUN mamba env update -q -p ${CONDA_DIR} -f /tmp/environment.yml
RUN mamba clean -afy
RUN rm -f /tmp/environment.yml

USER root
RUN rm -rf ${HOME}/.cache
RUN mkdir -p ${R_LIBS_USER}
# Create user owned R libs dir
# This lets users temporarily install packages
RUN install -d -o ${NB_USER} -g ${NB_USER} ${R_LIBS_USER}

# Prepare VS Code extensions
USER root
ENV VSCODE_EXTENSIONS=${CONDA_DIR}/share/code-server/extensions
RUN install -d -o ${NB_USER} -g ${NB_USER} ${VSCODE_EXTENSIONS} && \
    chown ${NB_USER}:${NB_USER} ${CONDA_DIR}/share/code-server

# Install R libraries as our user
USER ${NB_USER}
COPY --chown=1000:1000 install.R /tmp/
RUN Rscript /tmp/install.R
RUN rm -f /tmp/install.R

# Install IRKernel kernel
RUN R --quiet -e "IRkernel::installspec(prefix='${CONDA_DIR}')"

# Configure locking behavior
COPY file-locks /etc/rstudio/file-locks

USER ${NB_USER}
# installing chromium browser to enable webpdf conversion using nbconvert
ENV PLAYWRIGHT_BROWSERS_PATH=${CONDA_DIR}
RUN playwright install chromium

# https://github.com/berkeley-dsep-infra/datahub/issues/5827
RUN git config --system pull.rebase false

# overrides.json is a file that jupyterlab reads to determine some settings
# 1) remove the 'create shareable link' option from the filebrowser context menu
RUN mkdir -p ${CONDA_DIR}/share/jupyter/lab/settings
COPY overrides.json ${CONDA_DIR}/share/jupyter/lab/settings

# code-server's conda package assets are installed in share/code-server.
ENV VSCODE_EXTENSIONS=${CONDA_DIR}/share/code-server/extensions
RUN mkdir -p ${VSCODE_EXTENSIONS}

# This is not reproducible, and it can be difficult to version these.
RUN for x in \
  quarto.quarto \
  ms-vscode.live-server \
  posit.shiny \
  reditorsupport.r \
  ; do code-server --extensions-dir ${VSCODE_EXTENSIONS} --install-extension $x; done

ENV PATH=${CONDA_DIR}/bin:${R_LIBS_USER}/bin:${DEFAULT_PATH}:/usr/lib/rstudio-server/bin
COPY --chown=${NB_USER}:${NB_USER} .Renviron /home/${NB_USER}

WORKDIR /home/${NB_USER}

# Set SHELL so Jupyter launches /bin/bash, not /bin/sh
# /bin/sh doesn't have a lot of interactive features (like tab complete or functional arrow keys)
# that people have come to expect.
ENV SHELL=/bin/bash
EXPOSE 8888
