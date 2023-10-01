# Use Nvidia Cuda container base, sync the timezone to GMT, and install necessary package dependencies.
# Binaries are not available for some python packages, so pip must compile them locally. This is
# why gcc, g++, and python3.8-dev are included in the list below.
# Cuda 11.8 is used instead of 12 for backwards compatibility. Cuda 11.8 supports compute capability 
# 3.5 through 9.0
FROM nvidia/cuda:11.8.0-base-ubuntu20.04
ENV TZ=Etc/GMT
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    gcc \
    g++ \
    python3.8-dev \
    python3.8-venv \
    python3.9-venv \
    wget \
    portaudio19-dev \
    libsndfile1

# todo: Is there a better way to refer to the home directory (~)?
ARG HOME_DIR=/root

# Create virtual environments for so-vits-svc 3.0 and Hay Say's so_vits_svc_3_server
RUN python3.8 -m venv ~/hay_say/.venvs/so_vits_svc_3; \
    python3.9 -m venv ~/hay_say/.venvs/so_vits_svc_3_server

# Python virtual environments do not come with wheel, so we must install it. Upgrade pip while 
# we're at it to handle modules that use PEP 517
RUN ~/hay_say/.venvs/so_vits_svc_3/bin/pip install --timeout=300 --no-cache-dir --upgrade pip wheel; \
    ~/hay_say/.venvs/so_vits_svc_3_server/bin/pip install --timeout=300 --no-cache-dir --upgrade pip wheel

# Install all python dependencies for so-vits-svc 3.0.
# Note: This is done *before* cloning the repository because the dependencies are likely to change less often than the
# so-vits-svc 3.0 code itself. Cloning the repo after installing the requirements helps the Docker cache optimize build
# time. See https://docs.docker.com/build/cache
# Note: The requirements file does not specify a version number for several of the dependencies, which results in pip
# installing more recent versions of modules that conflict with older ones, so I have modified the requirements to
# include version numbers for everything. Furthermore, the requirements file is apparently missing librosa and
# torchvision, so I have added them too:
RUN ~/hay_say/.venvs/so_vits_svc_3/bin/pip install \
    --timeout=300 \
    --no-cache-dir \
    --extra-index-url https://download.pytorch.org/whl/cu113 \
	Flask==2.1.2 \
	Flask_Cors==3.0.10 \
	gradio==3.45.2 \
	numpy==1.19.2 \
	playsound==1.3.0 \
	PyAudio==0.2.12 \
	pydub==0.25.1 \
	pyworld==0.3.0 \
	requests==2.28.1 \
	scipy==1.7.3 \
	sounddevice==0.4.5 \
	SoundFile==0.10.3.post1 \
	starlette==0.19.1 \
	torch==1.10.0+cu113 \
	torchaudio==0.10.0+cu113 \
	tqdm==4.63.0 \
	scikit-maad==1.3.12 \
	praat-parselmouth==0.4.3 \
	onnx==1.13.1 \
	onnxsim==0.4.17 \
	onnxoptimizer==0.3.8 \
	pandas==1.4.4 \
	matplotlib==3.6.0 \
	scikit-image==0.19.3 \
	librosa==0.9.0 \
	torchvision==0.11.1

# Install the dependencies for the Hay Say interface code
RUN ~/hay_say/.venvs/so_vits_svc_3_server/bin/pip install \
    --timeout=300 \
    --no-cache-dir \
    hay-say-common==1.0.2 \
    jsonschema==4.19.1

# Download the pre-trained Hubert model checkpoint
RUN mkdir -p ~/hay_say/temp_downloads/hubert/ && \
    wget https://github.com/bshall/hubert/releases/download/v0.1/hubert-soft-0d54a1f4.pt --directory-prefix=/root/hay_say/temp_downloads/hubert/

# Expose port 6575, the port that Hay Say uses for so_vits_svc_3
EXPOSE 6575

# Download so_vits_svc_3 and checkout a specific commit that is known to work with this docker file and with Hay Say.
# IMPORTANT! Commit d9bdae2e9f279e5a72997cedac2e8023cf3367bd is the last one that used the MIT License before
# svc-develop-team switched to the GNU Affero General Public License. Using a commit that is later than
# d9bdae2e9f279e5a72997cedac2e8023cf3367bd may result in a licensing conflict because so_vits_svc_3_server is published
# under the Apache 2.0 License and it modifies a file from so-vits-svc-3.0 on-the-fly.
RUN git clone -b Mera-SVC-32k --single-branch -q https://github.com/svc-develop-team/so-vits-svc ~/hay_say/so_vits_svc_3
WORKDIR $HOME_DIR/hay_say/so_vits_svc_3
RUN git reset --hard d9bdae2e9f279e5a72997cedac2e8023cf3367bd

# Create the results directory. The directory would be automatically created by so-vits-svc 3.0 anyways, but
# so_vits_svc_3_server expects it to exist and creating it manually now prevents a rare bug that can occur in
# so_vits_svc_3_server on the very first run of the architecture.
RUN mkdir ~/hay_say/so_vits_svc_3/results

# Move the pre-trained Hubert model to the expected directory.
RUN mv /root/hay_say/temp_downloads/hubert/* /root/hay_say/so_vits_svc_3/hubert/

# Download the Hay Say Interface code
RUN git clone https://github.com/hydrusbeta/so_vits_svc_3_server ~/hay_say/so_vits_svc_3_server/

# Run the Hay Say Flask server on startup
CMD ["/bin/sh", "-c", "/root/hay_say/.venvs/so_vits_svc_3_server/bin/python /root/hay_say/so_vits_svc_3_server/main.py --cache_implementation file"]
