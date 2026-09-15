#ifndef DEMO_CHANNEL_CIPHER_H
#define DEMO_CHANNEL_CIPHER_H

#include <QByteArray>

/**
 * @brief The toy symmetric cipher this demo seals its encrypted channels with.
 *
 * DEMONSTRATION ONLY. It is a SHA-256 keystream with a SHA-256 tag, written to
 * be readable in one screen rather than to be sound — no KDF, no AEAD, no
 * replay protection. It exists so the demo can show `delivery_module` relaying
 * encrypt/decrypt to the module that owns a channel; a real consumer brings its
 * own vetted primitive.
 *
 * Wire layout: `nonce(8) || ciphertext || tag(16)`.
 */
namespace DemoChannelCipher {

/// A fresh 32-byte key as lowercase hex, for the UI's Generate button.
QString generateKeyHex();

/// Seals @p plain under @p key. Returns empty on an unusable key.
QByteArray seal(const QByteArray& key, const QByteArray& plain);

/// Opens what @ref seal produced. Returns empty when the tag does not check
/// out — a key the two participants do not share, or a truncated payload.
QByteArray open(const QByteArray& key, const QByteArray& sealed);

} // namespace DemoChannelCipher

#endif // DEMO_CHANNEL_CIPHER_H
