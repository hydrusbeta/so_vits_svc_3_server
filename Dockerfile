# Use Nvidia Cuda container base, sync the timezone to GMT, and install necessary package dependencies.
# Binaries are not available for some python packages, so pip must compile them locally. This is
# why gcc, g++, and python3.8-dev are included in the list below.
# Cuda 11.8 is used instead of 12 for backwards compatibility. Cuda 11.8 supports compute capability 
# 3.5 through 9.0
FROM nvidia/cuda:11.8.0-base-ubuntu20.04
ENV TZ=Etc/GMT
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone.
RUN apt-get update && apt-get install -y \
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

# download so_vits_svc_3 and checkout a specific commit that is known to work with this docker 
# file and with Hay Say.
RUN git clone -b 3.0-32k --single-branch -q https://github.com/svc-develop-team/so-vits-svc ~/hay_say/so_vits_svc_3
WORKDIR $HOME_DIR/hay_say/so_vits_svc_3
RUN git reset --hard 20c733901e283d62205c9bbe26afc2954172bd12

# Edit the requirements file.
# Explanation: The requirements file does not specify a version number for several of the dependencies,
# which results in pip installing more recent versions of modules that conflict with older ones, so 
# let's specify version numbers that are known to work. 
RUN sed -i 's/\bscikit-maad\b$/scikit-maad==1.3.12/' ~/hay_say/so_vits_svc_3/requirements.txt; \
    sed -i 's/\bpraat-parselmouth\b$/praat-parselmouth==0.4.3/' ~/hay_say/so_vits_svc_3/requirements.txt; \
    sed -i 's/\bonnx\b$/onnx==1.13.1/' ~/hay_say/so_vits_svc_3/requirements.txt;\
    sed -i 's/\bonnxsim\b$/onnxsim==0.4.17/' ~/hay_say/so_vits_svc_3/requirements.txt; \
    sed -i 's/\bonnxoptimizer\b$/onnxoptimizer==0.3.8/' ~/hay_say/so_vits_svc_3/requirements.txt; \
    echo "pandas==1.4.4" >> ~/hay_say/so_vits_svc_3/requirements.txt; \
    echo "matplotlib==3.6.0" >> ~/hay_say/so_vits_svc_3/requirements.txt; \
    echo "scikit-image==0.19.3" >> ~/hay_say/so_vits_svc_3/requirements.txt

# The requirements file is also apparently missing librosa and torchvision, so add them too:
RUN echo "librosa==0.9.0" >> ~/hay_say/so_vits_svc_3/requirements.txt; \
    echo "torchvision==0.11.1" >> ~/hay_say/so_vits_svc_3/requirements.txt

# Create virtual environments for so-vits-svc 3.0 and Hay Say's so_vits_svc_3_server
RUN python3.8 -m venv ~/hay_say/.venvs/so_vits_svc_3; \
    python3.9 -m venv ~/hay_say/.venvs/so_vits_svc_3_server

# Python virtual environments do not come with wheel, so we must install it. Upgrade pip while 
# we're at it to handle modules that use PEP 517
RUN ~/hay_say/.venvs/so_vits_svc_3/bin/pip install --no-cache-dir --upgrade pip wheel; \
    ~/hay_say/.venvs/so_vits_svc_3_server/bin/pip install --no-cache-dir --upgrade pip wheel

# Install all python dependencies for so_vits_svc_3 using the edited requirements file
RUN ~/hay_say/.venvs/so_vits_svc_3/bin/pip install --no-cache-dir -r ~/hay_say/so_vits_svc_3/requirements.txt --extra-index-url https://download.pytorch.org/whl/cu113

# Download the pre-trained Hubert model checkpoint
RUN wget https://github.com/bshall/hubert/releases/download/v0.1/hubert-soft-0d54a1f4.pt --directory-prefix=/root/hay_say/so_vits_svc_3/hubert/

# Download the Hay Say Interface code and install its dependencies
RUN git clone https://github.com/hydrusbeta/so_vits_svc_3_server ~/hay_say/so_vits_svc_3_server/ && \
    ~/hay_say/.venvs/so_vits_svc_3_server/bin/pip install --no-cache-dir -r ~/hay_say/so_vits_svc_3_server/requirements.txt

# Expose port 6575, the port that Hay Say uses for so_vits_svc_3
EXPOSE 6575

# Run the Hay Say Flask server on startup
CMD ["/bin/sh", "-c", "/root/hay_say/.venvs/so_vits_svc_3_server/bin/python /root/hay_say/so_vits_svc_3_server/main.py"]
