#include "demo_channel_cipher.h"

#include <QCryptographicHash>
#include <QRandomGenerator>
#include <QString>

namespace {

constexpr int kNonceLen = 8;
constexpr int kTagLen = 16;

QByteArray keystream(const QByteArray& key, const QByteArray& nonce, int length)
{
    QByteArray out;
    out.reserve(length);
    for (quint32 block = 0; out.size() < length; ++block) {
        QCryptographicHash h(QCryptographicHash::Sha256);
        h.addData(key);
        h.addData(nonce);
        h.addData(QByteArray(reinterpret_cast<const char*>(&block), sizeof(block)));
        out.append(h.result());
    }
    out.truncate(length);
    return out;
}

QByteArray tag(const QByteArray& key, const QByteArray& nonce, const QByteArray& ciphertext)
{
    QCryptographicHash h(QCryptographicHash::Sha256);
    h.addData(QByteArrayLiteral("tag"));
    h.addData(key);
    h.addData(nonce);
    h.addData(ciphertext);
    return h.result().left(kTagLen);
}

QByteArray xorWith(const QByteArray& in, const QByteArray& pad)
{
    QByteArray out = in;
    for (int i = 0; i < out.size(); ++i) {
        out[i] = static_cast<char>(out[i] ^ pad[i]);
    }
    return out;
}

} // namespace

namespace DemoChannelCipher {

QString generateKeyHex()
{
    QByteArray key(32, Qt::Uninitialized);
    QRandomGenerator::system()->generate(key.begin(), key.end());
    return QString::fromLatin1(key.toHex());
}

QByteArray seal(const QByteArray& key, const QByteArray& plain)
{
    if (key.isEmpty()) {
        return {};
    }
    QByteArray nonce(kNonceLen, Qt::Uninitialized);
    QRandomGenerator::system()->generate(nonce.begin(), nonce.end());

    const QByteArray ciphertext = xorWith(plain, keystream(key, nonce, plain.size()));
    return nonce + ciphertext + tag(key, nonce, ciphertext);
}

QByteArray open(const QByteArray& key, const QByteArray& sealed)
{
    if (key.isEmpty() || sealed.size() < kNonceLen + kTagLen) {
        return {};
    }
    const QByteArray nonce = sealed.left(kNonceLen);
    const QByteArray ciphertext = sealed.mid(kNonceLen, sealed.size() - kNonceLen - kTagLen);
    if (sealed.right(kTagLen) != tag(key, nonce, ciphertext)) {
        return {};
    }
    return xorWith(ciphertext, keystream(key, nonce, ciphertext.size()));
}

} // namespace DemoChannelCipher
