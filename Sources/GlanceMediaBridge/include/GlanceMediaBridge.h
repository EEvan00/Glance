#ifndef GLANCE_MEDIA_BRIDGE_H
#define GLANCE_MEDIA_BRIDGE_H
double GlanceMediaMetadataRetryDelay(double duration, unsigned int state, unsigned int attempt);
void glance_media_stream(void);
void glance_media_command(void);
#endif
