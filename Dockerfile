FROM ros:humble-ros-base

# ROS 2 environment variables. ROS_LOCALHOST_ONLY defaults to 0 so the
# container can discover a TIAGo on another host (use --network host).
ENV ROS_DISTRO=humble
ENV ROS_DOMAIN_ID=0
ENV ROS_LOCALHOST_ONLY=0
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp

# TIAGo defaults (override at `docker run` with -e if your robot differs).
ENV MAP_FRAME=map
ENV BASE_FRAME=base_footprint
# opennav_docking is Jazzy+, so keep docking off on Humble.
ENV ENABLE_DOCKING=0

# Nav2 Python deps come from apt (NOT PyPI): rclpy, nav2_simple_commander,
# tf2_ros, and the message packages are all provided by the ROS install.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    ros-${ROS_DISTRO}-nav2-simple-commander \
    ros-${ROS_DISTRO}-nav2-msgs \
    ros-${ROS_DISTRO}-tf2-ros-py \
    ros-${ROS_DISTRO}-geometry-msgs \
    ros-${ROS_DISTRO}-nav-msgs \
    ros-${ROS_DISTRO}-lifecycle-msgs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy metadata + source, then install the package into the system
# environment so it sits alongside the apt-provided ROS Python packages.
COPY pyproject.toml README.md ./
COPY src/ src/
RUN pip3 install --no-cache-dir .

# /ros_entrypoint.sh (provided by the ros base image) sources the ROS
# environment before exec'ing the command, so rclpy & friends import.
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["python3", "-m", "nav2_mcp_server"]
